# Copyright (C) 2015-2017 Yoann Le Garff, Nicolas Boquet and Yann Le Bras
# navel-dispatcher is licensed under the Apache License, Version 2.0

#-> BEGIN

#-> initialization

package Navel::Dispatcher::Mojolicious::Application 0.1;

use parent 'Navel::Base::Daemon::Mojolicious::Application';

use Navel::API::OpenAPI::Dispatcher;

#-> methods

sub new {
    my $class = shift;

    $class->SUPER::new(
        @_,
        openapi => Navel::API::OpenAPI::Dispatcher->new
    );
}

# sub AUTOLOAD {}

# sub DESTROY {}

1;

#-> END

__END__

=pod

=encoding utf8

=head1 NAME

Navel::Dispatcher::Mojolicious::Application

=head1 COPYRIGHT

Copyright (C) 2015-2017 Yoann Le Garff, Nicolas Boquet and Yann Le Bras

=head1 LICENSE

navel-dispatcher is licensed under the Apache License, Version 2.0

=cut
