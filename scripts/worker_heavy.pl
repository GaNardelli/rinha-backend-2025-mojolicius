#!/usr/bin/env perl
use strict;
use JSON;
use DateTime;
use Data::Dumper;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Mojo::Redis;
use Mojo::Pg;

# Setup
my $postgres_dsn = $ENV{"POSTGRES_DSN"} // 'postgresql://monk:rinha_2025@localhost:5432/payments';
my $redis_url    = $ENV{"APP_ENV"} && $ENV{"APP_ENV"} eq 'docker'
  ? 'redis://redis:6379'
  : 'redis://localhost:6379';

my $postgres = Mojo::Pg->new($postgres_dsn);
my $database = $postgres->db;

my $redis = Mojo::Redis->new($redis_url);
my $ua = Mojo::UserAgent->new->inactivity_timeout(3);

# Fallback porta local
my $payment_ports = {
  default  => 8001,
  fallback => 8002
};

# Loop de polling da fila Redis
sub wait_for_next_message {
    my $promise = $redis->db->brpop_p('payment_process_queue', 0)->then(sub {
        my ($payload) = @_;
        # warn "Callback do brpop chamado\n";
        return wait_for_next_message() unless defined $payload;
        # warn $payload;
        my $message = eval { decode_json $payload };
        unless ($message) {
            # warn "Erro ao decodificar JSON da fila: $@";
            return wait_for_next_message();
        }

        # Buscar processador atual
        return $redis->db->get_p('payment_processor')->then(sub {
            my ($raw) = @_;
            # warn "Raw: $raw";
            unless ($raw) {
                # warn "Chave Redis 'payment_processor' não encontrada";
                return wait_for_next_message();
            }

            my $best_processor = eval { decode_json $raw };
            unless ($best_processor) {
                # warn "Erro ao decodificar JSON do Redis: $@";
                return wait_for_next_message();
            }

            my $send_payload = {
                correlationId => $message->{correlationId},
                amount => $message->{amount},
            };
            my $actual_time = DateTime->now->iso8601() . 'Z';
            # warn "Send Payload: " . Dumper($send_payload);
            # warn "Best Processor URL: $best_processor->{url}";
            # warn "Best Processor payment_processor: $best_processor->{payment_processor}";
            my $url = $best_processor->{url} || "http://localhost:$payment_ports->{$best_processor->{payment_processor}}/payments";
            # warn "URL: $url";
            $ua->post($url => {'Content-Type' => 'application/json'} => json => $send_payload => sub {
                my ($ua, $tx) = @_;
                my $res = $tx->result;
                # warn Dumper($tx->result);
                if ($res->is_success) {
                    eval {
                    $database->insert('payments', {
                        correlation_id => $send_payload->{correlationId},
                        amount => $send_payload->{amount},
                        requested_at => $actual_time,
                        processor => $best_processor->{payment_processor}
                    });
                    # warn "Processado e inserido: $send_payload->{correlationId}";
                    } or do {
                        # warn "Falha no insert no Postgres: $@"
                    };
                } else {
                    # warn "Erro ao enviar para processador: " . $res->code;
                }
                wait_for_next_message();
            });
            # Aguarda próxima mensagem após a resposta
        })->catch(sub {
            # warn "Erro no brpop: @_";
            wait_for_next_message();
        });
    })->catch(sub {
        # warn "Erro no brpop: @_";
        wait_for_next_message();
    });
}

# Inicia loop
Mojo::IOLoop->timer(3 => sub {
    wait_for_next_message();
});
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
