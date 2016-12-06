# Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras
# navel-dispatcher is licensed under the Apache License, Version 2.0

#-> BEGIN

#-> initialization

package Navel::Dispatcher::Core::Storekeeper::Fork 0.1;

use Navel::Base;

use parent 'Navel::Base::WorkerManager::Core::Worker::Fork';

#-> methods

sub wrapped_code {
    my $self = shift;

    'package ' . $self->{worker_package} . " 0.1;

BEGIN {
    open STDIN, '</dev/null';
    open STDOUT, '>/dev/null';
    open STDERR, '>&STDOUT';
}" . '

use Navel::Base;

use URI;
use AnyEvent::HTTP;

use Navel::Queue;
use Navel::Notification;
use Navel::Utils ' . "'json_constructor'" . ';

BEGIN {
    require ' . $self->{definition}->{consumer_backend} . ';
    require ' . $self->{definition}->{publisher_backend} . ';
}

my ($initialized, $exiting, %database);

my $json_constructor = json_constructor;

*log = \&AnyEvent::Fork::RPC::event;

sub consumer_queue {
    state $queue = Navel::Queue->new(
        size => ' . $self->{definition}->{consumer_queue_size} . '
    );
}

sub publisher_queue {
    state $queue = Navel::Queue->new(
        size => ' . $self->{definition}->{publisher_queue_size} . '
    );
}

sub ' . $self->{worker_rpc_method} . ' {
    my ($done, $backend, $sub, $meta, $storekeeper) = @_;

    if ($exiting) {
        $done->(0, ' . "'currently exiting the worker'" . ');

        return;
    }

    unless ($initialized) {
        $initialized = 1;

        *meta = sub {
            $meta;
        };

        *storekeeper = sub {
            $storekeeper;
        };

        ' . $self->{definition}->{consumer_backend} . '::init;
        ' . $self->{definition}->{publisher_backend} . '::init;

        $database{uri} = URI->new;

        $database{uri}->scheme(' . "'http' . (storekeeper()->{database_tls} ? 's' : ''));" . '
        $database{uri}->userinfo(' . "storekeeper()->{database_user} . (defined storekeeper()->{database_password} ? ':' . storekeeper()->{database_password} : ''))" . ' if defined storekeeper()->{database_user};
        $database{uri}->host(storekeeper()->{database_host});
        $database{uri}->port(storekeeper()->{database_port});
        $database{uri}->path(storekeeper()->{database_basepath});

        $database{as_string} = $database{uri}->as_string;
    }

    unless (defined $backend) {
        if ($sub eq ' . "'consumer_queue'" . ') {
            $done->(1, scalar @{consumer_queue->{items}});
        } elsif ($sub eq ' . "'consumer_dequeue'" . ') {
            $done->(1, scalar consumer_queue->dequeue);
        } elsif ($sub eq ' . "'publisher_queue'" . ') {
            $done->(1, scalar @{publisher_queue->{items}});
        } elsif ($sub eq ' . "'publisher_dequeue'" . ') {
            $done->(1, scalar publisher_queue->dequeue);
        } elsif ($sub eq ' . "'database_active_connections'" . ') {
            $done->(1, $AnyEvent::HTTP::ACTIVE);
        } elsif ($sub eq ' . "'batch'" . ') {
            my $events = consumer_queue->dequeue;

            http_post(
                $database{as_string},
                $json_constructor->encode($events),
                {
                    tls_ctx => {
                        verify => storekeeper()->{database_tls_verify},
                        ca_cert => storekeeper()->{database_tls_ca_cert}
                    }
                },
                sub {
                    my ($body, $headers) = @_;

                    my $on_error = sub {
                        my $message = shift;

                        my $size_left = consumer_queue->size_left;

                        consumer_queue->enqueue($size_left < 0 ? @{$events} : splice @{$events}, - ($size_left > @{$events} ? @{$events} : $size_left));

                        $done->(0, $message);
                    };

                    if (substr($headers->{Status}, 0, 1) eq ' . "'2'" . ') {
                        local $@;

                        my @responses = eval {
                            @{$json_constructor->decode($body)};
                        };

                        unless ($@) {
                            my $errors = 0;

                            for (@responses) {
                                eval {
                                    publisher_queue->enqueue(Navel::Notification->new(%{$_})->serialize);
                                };

                                $errors++ if $@;
                            }

                            log(
                                [
                                    ' . "'warning',
                                    \$errors . ' notification(s) could not be created.'" . '
                                ]
                            ) if $errors;

                            $done->(1);
                        } else {
                            $on_error->(' . "'the remote database returned an unexpected response: '" . ' . $@);
                        }
                    } else {
                        $on_error->(' . "'the remote database returned an unexpected response: HTTP ' . \$headers->{Status} . ' - '" . ' . $headers->{Reason});
                    }
                }
            );
        } else {
            $exiting = 1;

            $done->(1);

            exit;
        }

        return;
    }

    if (my $sub_ref = $backend->can($sub)) {
        $sub_ref->($done);
    } else {
        $done->(0, ' . "\$backend . '::' . \$sub . ' is not declared'" . ');
    }

    return;
}

1;';
}

# sub AUTOLOAD {}

# sub DESTROY {}

1;

#-> END

__END__

=pod

=encoding utf8

=head1 NAME

Navel::Dispatcher::Core::Storekeeper::Fork

=head1 COPYRIGHT

Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras

=head1 LICENSE

navel-dispatcher is licensed under the Apache License, Version 2.0

=cut
