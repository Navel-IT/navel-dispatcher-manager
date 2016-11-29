# Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras
# navel-dispatcher is licensed under the Apache License, Version 2.0

#-> BEGIN

#-> initialization

package Navel::Dispatcher::Core 0.1;

use Navel::Base;

use parent 'Navel::Base::WorkerManager::Core';

use Promises qw/
    deferred
    collect
/;

use Navel::Logger::Message;
use Navel::Definition::Storekeeper::Parser;
use Navel::AnyEvent::Pool;
use Navel::Dispatcher::Core::Storekeeper::Fork;
use Navel::Utils 'croak';

#-> methods

sub new {
    my ($class, %options) = @_;

    my $self = $class->SUPER::new(%options);

    $self->{definitions} = Navel::Definition::Storekeeper::Parser->new(
        maximum => $self->{meta}->{definition}->{storekeepers}->{maximum}
    )->read(
        file_path => $self->{meta}->{definition}->{storekeepers}->{definitions_from_file}
    )->make;

    $self->{job_types} = {
        %{$self->{job_types}},
        %{
            {
                storekeeper => Navel::AnyEvent::Pool->new(
                    logger => $options{logger},
                    maximum => $self->{meta}->{definition}->{storekeepers}->{maximum}
                )
            }
        }
    };

    bless $self, ref $class || $class;
}

sub init_worker_by_name {
    my $self = shift;

    my $definition = $self->{definitions}->definition_by_name(shift);

    die "unknown definition\n" unless defined $definition;

    $self->{logger}->notice($definition->full_name . ': initialization.');

    my $on_event_error_message_prefix = $definition->full_name . ': incorrect behavior/declaration.';

    $self->{worker_per_definition}->{$definition->{name}} = Navel::Dispatcher::Core::Storekeeper::Fork->new(
        core => $self,
        definition => $definition,
        on_event => sub {
            local $@;

            for (@_) {
                if (ref eq 'ARRAY') {
                    eval {
                        $self->{logger}->enqueue(
                            severity => $_->[0],
                            text => $definition->full_name . ': ' . $_->[1]
                        ) if defined $_->[1];
                    };

                    $self->{logger}->err(
                        Navel::Logger::Message->stepped_message($on_event_error_message_prefix,
                            [
                                $@
                            ]
                        )
                    ) if $@;
                } else {
                    $self->{logger}->err(
                        Navel::Logger::Message->stepped_message($on_event_error_message_prefix,
                            [
                                'event must be a ARRAY reference.'
                            ]
                        )
                    );
                }
            }
        },
        on_error => sub {
            $self->{logger}->warning($definition->full_name . ': execution stopped (fatal): ' . shift . '.');
        },
        on_destroy => sub {
            $self->{logger}->info($definition->full_name . ': destroyed.');
        }
    );

    $self;
}

my $worker_timer_callback_common_workflow = sub {
    my ($self, $worker, $timer, $interface_type) = @_;

    my $interface_backend = $interface_type . '_backend';

    my $deferred = deferred;

    $worker->rpc(
        $worker->{definition}->{$interface_backend},
        'is_connectable'
    )->then(
        sub {
            if (shift) {
                $self->{logger}->debug($worker->{definition}->full_name . ': ' . $timer->full_name . ': the associated ' . $interface_type . ' is apparently connectable.');

                collect(
                    $worker->rpc($worker->{definition}->{$interface_backend}, 'is_connected'),
                    $worker->rpc($worker->{definition}->{$interface_backend}, 'is_connecting')
                );
            } else {
                (
                    [
                        1
                    ],
                    [
                        0
                    ]
                );
            }
        }
    )->then(
        sub {
            unless (shift->[0]) {
                if (shift->[0]) {
                    die 'connecting of the associated ' . $interface_type . " is in progress, cannot continue\n";
                } else {
                    $self->{logger}->debug($worker->{definition}->full_name . ': ' . $timer->full_name . ': starting connection of the associated ' . $interface_type . '.');

                    $worker->rpc($worker->{definition}->{$interface_backend}, 'connect');
                }
            }
        }
    )->then(
        sub {
            $deferred->resolve;
        }
    )->catch(
        sub {
            $deferred->reject(@_);
        }
    );

    $deferred->promise;
};

sub register_worker_by_name {
    my ($self, $name) = @_;

    croak('name must be defined') unless defined $name;

    my $worker = $self->{worker_per_definition}->{$name};

    die "unknown worker\n" unless defined $worker;

    my $on_catch = sub {
        $self->{logger}->warning(
            Navel::Logger::Message->stepped_message($worker->{definition}->full_name . ': chain of action cannot be completed.', \@_)
        );
    };

    $self->unregister_job_by_type_and_name('storekeeper', $worker->{definition}->{name})->pool_matching_job_type('storekeeper')->attach_timer(
        name => $worker->{definition}->{name},
        singleton => 1,
        splay => 1,
        interval => 1,
        callback => sub {
            my $timer = shift->begin;

            collect(
                $self->$worker_timer_callback_common_workflow($worker, $timer, 'consumer'),
                $self->$worker_timer_callback_common_workflow($worker, $timer, 'publisher')
            )->then(
                sub {
                    $worker->rpc(undef, 'batch');
                }
            )->then(
                sub {
                    $self->{logger}->notice($worker->{definition}->full_name . ': ' . $timer->full_name . ': chain of action successfully completed.');
                }
            )->catch($on_catch)->finally(
                sub {
                    $timer->end;
                }
            );
        },
        on_enable => sub {
            my $timer = shift;

            collect(
                $worker->rpc($worker->{definition}->{consumer_backend}, 'enable'),
                $worker->rpc($worker->{definition}->{publisher_backend}, 'enable')
            )->then(
                sub {
                    $self->{logger}->notice($worker->{definition}->full_name . ': ' . $timer->full_name . ': chain of activation successfully completed.');
                }
            )->catch($on_catch);
        },
        on_disable => sub {
            my $timer = shift;

            collect(
                $worker->rpc($worker->{definition}->{consumer_backend}, 'disable'),
                $worker->rpc($worker->{definition}->{publisher_backend}, 'disable')
            )->then(
                sub {
                    $self->{logger}->notice($worker->{definition}->full_name . ': ' . $timer->full_name . ': chain of deactivation successfully completed.');
                }
            )->catch($on_catch);
        }
    );

    $self;
}

sub delete_worker_and_definition_associated_by_name {
    my $self = shift;

    $self->SUPER::delete_worker_and_definition_associated_by_name('storekeeper', @_);

    $self;
}


# sub AUTOLOAD {}

# sub DESTROY {}

1;

#-> END

__END__

=pod

=encoding utf8

=head1 NAME

Navel::Dispatcher::Core

=head1 COPYRIGHT

Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras

=head1 LICENSE

navel-dispatcher is licensed under the Apache License, Version 2.0

=cut
