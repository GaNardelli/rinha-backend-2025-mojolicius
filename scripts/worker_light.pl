#!/usr/bin/env perl
use strict;
# use warnings;
use Data::Dumper;
use JSON;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Mojo::Redis;

my $ua = Mojo::UserAgent->new;

my $redis_url = defined($ENV{"APP_ENV"}) && $ENV{"APP_ENV"} eq 'docker' ? 'redis://redis:6379' : 'redis://localhost:6379';
my $payment_processor_default = $ENV{"PROCESSOR_DEFAULT_URL"} || 'http://localhost:8001';
my $payment_processor_fallback = $ENV{"PROCESSOR_FALLBACK_URL"} || 'http://localhost:8002';

my $redis = Mojo::Redis->new($redis_url);

my $url_default = "$payment_processor_default/payments/service-health";
my $url_fallback = "$payment_processor_fallback/payments/service-health";

my $url_payment_default = "$payment_processor_default/payments";
my $url_payment_fallback = "$payment_processor_fallback/payments";
$redis->db->set("payment_processor" => JSON::encode_json {url => $url_payment_default, payment_processor => "default"});

Mojo::IOLoop->recurring(5 => sub {
    # warn "Getting the better payment method.";
    my $best_url = $url_payment_default;
    my $best_payment_processor = 'default';
    my $result_default;
    my $result_fallback;
    my $tx_default = $ua->get($url_default);
    eval {
        $result_default = JSON::decode_json $tx_default->result->body;
    } or do {
        # warn "Error getting the processor default health: $@";
        return;
    };
    if ($result_default->{'failing'} eq 0) {
        # warn "Setting default";
        $redis->db->set("payment_processor" => JSON::encode_json {url => $best_url, payment_processor => $best_payment_processor});
    }
    my $tx_fallback = $ua->get($url_fallback);
    eval {
        $result_fallback = JSON::decode_json $tx_fallback->result->body;
    } or do {
        # warn "Error getting the processor fallback health: $@";
        return;
    };
    if ($result_default->{'failing'} eq 1 && $result_fallback->{'failing'} eq 0) {
        # warn "Setting fallback";
        $best_url = $url_payment_fallback;
        $best_payment_processor = 'fallback';
        $redis->db->set("payment_processor" => JSON::encode_json {url => $best_url, payment_processor => $best_payment_processor});
    }
    if ($result_default->{'failing'} eq 1 && $result_fallback->{'failing'} eq 1) {
        $best_url = $result_default->{'minResponseTime'} > $result_fallback->{'minResponseTime'} ? $url_payment_fallback : $url_payment_default;
        # warn "Setting $best_url";
        $best_payment_processor = $result_default->{'minResponseTime'} > $result_fallback->{'minResponseTime'} ? 'fallback' : 'default';
        $redis->db->set("payment_processor" => JSON::encode_json {url => $best_url, payment_processor => $best_payment_processor});
    }
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;