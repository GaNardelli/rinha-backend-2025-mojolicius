#!/usr/bin/env perl
use strict;
use warnings;
use Mojo::UserAgent;
use Minion;
use Mojo::IOLoop;

my $minion = Minion->new(Redis => 'redis://redis:6379');
my $ua = Mojo::UserAgent->new;
my $url = 'http://api1:3000/health';

Mojo::IOLoop->recurring(5 => sub {
    my $tx = $ua->get($url);
    if (my $res = $tx->result) {
        $minion->enqueue(check_payment => [$res->body]);
        print "Enfileirado job check_payment\n";
    } else {
        warn "Falha ao consultar $url: " . $tx->error->{message} . "\n";
    }
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;