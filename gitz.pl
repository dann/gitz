#!/usr/bin/env perl
use strict;
use warnings;

=head1 DESCRIPTION

This is a command-line interface to github issues API.

=cut

use Encode;
use Getopt::Long;
use JSON::XS;
use LWP::UserAgent;
use Pod::Usage;
use Config::Pit;
use Perl6::Say;

our $ua         = LWP::UserAgent->new;
our %config     = ();
our %args       = ();
our $CONFIG_KEY = 'developer.github.com';
our $API_BASE   = "http://github.com/api/v2/json/issues";
our $project;

$ua->env_proxy;

main();

sub main {
    setup_encoding();
    setup_config();
    setup_options();
    setup_project_name();
    my $commands = setup_commands();
    my $command = shift @ARGV || "todo";
    dispatch_command( $commands, $command );
}

sub setup_encoding {
    my $encoding;
    eval {
        require Term::Encoding;
        $encoding = Term::Encoding::get_encoding();
    };
    $encoding ||= "utf-8";
    binmode STDOUT, ":encoding($encoding)";
    binmode STDIN,  ":encoding($encoding)";
    @ARGV = map decode( $encoding, $_ ), @ARGV;
}

sub setup_config {
    my $config = pit_get(
        "developer.github.com",
        require => {
            "username"  => "your username on github",
            "api_token" => "your api token on github"
        }
    );
    %config = %$config;
    $config;
}

sub setup_options {
    GetOptions( \%args, "title=s", "body=s", "help", "project=s" )
        or pod2usage(2);
    pod2usage(0) if $args{help};
}

sub setup_project_name {
    $project = $args{project} || $ENV{GITZ_PROJECT};
    die 'project name is required' unless $project;
    $project;
}

sub setup_commands {
    {   todo   => \&list_issue,
        add    => \&add_issue,
        close  => \&close_issue,
        reopen => \&reopen_issue,
        show   => \&show_issue,
        edit   => \&edit_issue,
    };
}

sub dispatch_command {
    my ( $commands, $command ) = @_;
    $commands->{$command}
        or
        pod2usage( -message => "Unknown command: $command", -exitval => 2 );
    $commands->{$command}->();
}

sub call_get_api {
    my ( $method, $param ) = @_;
    my $api_url = _api_url( $method, $param );
    my $res = $ua->get($api_url) or die 'oops';
    my $content = $res->decoded_content;
    return decode_json($content);
}

sub call_post_api {
    my ( $method, $url_param, $post_params ) = @_;
    my $api_url = _api_url( $method, $url_param );
    my $config  = pit_get($CONFIG_KEY);
    my $form    = {
        login => $config->{username},
        token => $config->{api_token},
        %{ $post_params || {} },
    };

    my $res = $ua->post( $api_url, $form ) or die 'oops';
    my $content = $res->decoded_content;
    return decode_json($content);
}

sub _api_url {
    my ( $method, $param ) = @_;
    my $config    = pit_get($CONFIG_KEY);
    my $username  = $config->{username};
    my $api_token = $config->{api_token};
    my $api_url   = "${API_BASE}/${method}/${username}/${project}/${param}";
    $api_url;
}

# commands
sub list_issue {
    my $issues = call_get_api( 'list', 'open' );
    foreach my $issue ( @{ $issues->{issues} || [] } ) {
        my $formatted
            = sprintf( "%3d: %s", $issue->{number}, $issue->{title} );
        say $formatted;
    }
}

sub show_issue {
    my $id     = shift @ARGV;
    die 'id is required' unless $id;
    my $issues = call_get_api( 'show', $id );
    my $issue  = $issues->{issue};
    return unless $issue;
    my $formatted = sprintf( "%3d: %s - %s", $issue->{number}, $issue->{title}, $issue->{body} );
    say $formatted;
}

sub close_issue {
    my $id = shift @ARGV;
    die 'id is required' unless $id;
    call_post_api( 'close', $id );
}

sub edit_issue {
    my $id = shift @ARGV;
    die 'id is required' unless $id;
    die 'title is required ' unless $args{title};
    die 'body is required '  unless $args{body};

    call_post_api(
        'edit', 
        $id,
        {   title => $args{title},
            body  => $args{body}
        }
    );
}

sub reopen_issue {
    my $id = shift @ARGV;
    die 'id is required' unless $id;
    call_post_api( 'reopen', $id );
}

sub add_issue {
    die 'title is required ' unless $args{title};
    die 'body is required '  unless $args{body};
    call_post_api(
        'open', '',
        {   title => $args{title},
            body  => $args{body}
        }
    );
}

__END__

=head1 NAME

gitz.pl - a command-line interface to github issues

=head1 SYNOPSIS

    gitz.pl todo --project angelos
    gitz.pl close --project angelos
    gitz.pl add --title XXX --body YYY --project angelos
    gitz.pl edit 1 --title XXX --body YYY --project angelos
    gitz.pl show 1 --project angelos
    gitz.pl close 1 --project angelos
    gitz.pl reopen 1 --project angelos

  you can set project name with enviornment variable like below:

    export GITZ_PROJECT=angelos

=cut

