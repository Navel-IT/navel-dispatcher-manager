# Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras
# navel-dispatcher is licensed under the Apache License, Version 2.0

#-> BEGIN

#-> initialization

package Navel::Dispatcher::Mojolicious::Application::Controller::OpenAPI::Storekeeper 0.1;

use Navel::Base;

use Mojo::Base 'Mojolicious::Controller';

use parent 'Navel::Base::WorkerManager::Mojolicious::Application::Controller::OpenAPI::Worker';

#-> methods

sub show_associated_database_connection_status {
    my $controller = shift->openapi->valid_input || return;

    my $name = $controller->validation->param('name');

    my $definition = $controller->daemon->{core}->{definitions}->definition_by_name($name);

    return $controller->resource_not_found($name) unless defined $definition;

    $controller->render_later;

    $controller->daemon->{core}->{worker_per_definition}->{$definition->{name}}->rpc(undef, 'database_active_connections')->then(
        sub {
            $controller->render(
                openapi => {
                    active_connections => shift
                },
                status => 200
            );
        }
    )->catch(
        sub {
            $controller->render(
                openapi => $controller->ok_ko(
                    [],
                    [
                        (@_ ? join ', ', @_ : 'unexpected error') . ' (database_active_connections).'
                    ]
                ),
                status => 500
            );
        }
    );
}

sub show_associated_consumer_queue {
    shift->_show_associated_queue('consumer_queue');
}

sub delete_all_events_from_associated_consumer_queue {
    shift->_delete_all_events_from_associated_queue('consumer_queue');
}

sub show_associated_consumer_connection_status {
    shift->_show_associated_pubsub_connection_status('consumer_backend');
}

sub show_associated_publisher_queue {
    shift->_show_associated_queue('publisher_queue');
}

sub delete_all_events_from_associated_publisher_queue {
    shift->_delete_all_events_from_associated_queue('publisher_queue');
}

sub show_associated_publisher_connection_status {
    shift->_show_associated_pubsub_connection_status('publisher_backend');
}

# sub AUTOLOAD {}

# sub DESTROY {}

1;

#-> END

__END__

=pod

=encoding utf8

=head1 NAME

Navel::Dispatcher::Mojolicious::Application::Controller::OpenAPI::Storekeeper

=head1 COPYRIGHT

Copyright (C) 2015-2016 Yoann Le Garff, Nicolas Boquet and Yann Le Bras

=head1 LICENSE

navel-dispatcher is licensed under the Apache License, Version 2.0

=cut
