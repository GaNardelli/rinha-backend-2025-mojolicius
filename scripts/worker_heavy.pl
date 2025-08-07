#!/usr/bin/env perl
use strict;
use JSON;
use Data::Dumper;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Mojo::Redis;
use Mojo::Pg;

my $BUFFER_MAX_SIZE = 100;
my $FLUSH_INTERVAL = 0.5;

# Setup
my $postgres_dsn = $ENV{"POSTGRES_DSN"} // 'postgresql://monk:rinha_2025@localhost:5432/payments';
my $redis_url    = $ENV{"APP_ENV"} && $ENV{"APP_ENV"} eq 'docker'
  ? 'redis://redis:6379'
  : 'redis://localhost:6379';

my $postgres = Mojo::Pg->new($postgres_dsn);

my $redis = Mojo::Redis->new($redis_url);
my $ua = Mojo::UserAgent->new();

# Fallback porta local
my $payment_ports = {
  default  => 8001,
  fallback => 8002
};

my @buffer;
my $flushing = 0;

sub flush_buffer {
    return if $flushing == 1;
    return if @buffer <= 0;
    # warn "Bulk inserting " . scalar(@buffer) ." registers";
    $flushing = 1;
    my $placeholders = join(', ', map { '(?, ?, ?, ?)' } @buffer);
    my @values = map { @$_{qw/correlation_id amount requested_at processor/} } @buffer;
    eval {
        my $database = $postgres->db;
        my $tx = $database->begin;
        $database->query(
            "INSERT INTO payments (correlation_id, amount, requested_at, processor) 
            VALUES $placeholders
            ON CONFLICT (correlation_id) DO NOTHING",
            @values
        );
        $tx->commit;
    };
    @buffer = ();
    # warn $@ if $@;
    $flushing = 0;
    # warn "Bulk insert completed.";
    return;
}

Mojo::IOLoop->recurring($FLUSH_INTERVAL => sub { 
    # warn "Flushing " . scalar(@buffer) ." registers";
    flush_buffer();
});

# Loop de polling da fila Redis
sub wait_for_next_message {
    my $promise = $redis->db->lpop_p('payment_process_queue')->then(sub {
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
                requested_at => $message->{requested_at}
            };
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
                        push @buffer, {
                            correlation_id => $send_payload->{correlationId},
                            amount => $send_payload->{amount},
                            requested_at => $send_payload->{requested_at},
                            processor => $best_processor->{payment_processor}
                        };
                        
                        flush_buffer() if @buffer >= $BUFFER_MAX_SIZE;
                        # warn "Processado e inserido: $send_payload->{correlationId}";
                        # my $database = $postgres->db;
                        # $database->insert('payments', {
                        #     correlation_id => $send_payload->{correlationId},
                        #     amount => $send_payload->{amount},
                        #     requested_at => $send_payload->{requested_at},
                        #     processor => $best_processor->{payment_processor}
                        # });
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
Mojo::IOLoop->timer(0 => sub {
    wait_for_next_message() for (1..10);
});
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
