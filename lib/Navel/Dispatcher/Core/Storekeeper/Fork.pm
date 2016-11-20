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

use Navel::Queue;

BEGIN {
    require ' . $self->{definition}->{consumer_backend} . ';
    require ' . $self->{definition}->{publisher_backend} . ';
}

my ($initialized, $exiting);

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

    unless (defined $backend) {
        if ($sub eq ' . "'consumer_queue'" . ') {
            $done->(1, scalar @{consumer_queue->{items}});
        } elsif ($sub eq ' . "'consumer_dequeue'" . ') {
            $done->(1, scalar consumer_queue->dequeue);
        } elsif ($sub eq ' . "'publisher_queue'" . ') {
            $done->(1, scalar @{publisher_queue->{items}});
        } elsif ($sub eq ' . "'publisher_dequeue'" . ') {
            $done->(1, scalar publisher_queue->dequeue);
        } else {
            $exiting = 1;

            $done->(1, ' . "'exiting the worker'" . ');

            exit;
        }

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
