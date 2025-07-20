FROM debian:bookworm-slim

WORKDIR /opt/

COPY . .

RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libexpat1-dev \
    libz-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN cpan App::cpanminus

RUN cpanm --no-test Mojolicious Minion::Worker Mojo::Redis Minion Minion::Backend::Redis Mojo::UserAgent Mojo::IOLoop JSON

EXPOSE 3000

CMD ["morbo", "./scripts/PaymentHandler"]
# Usar em produção
# CMD ["./scripts/PaymentHandler", "prefork", "-m", "production", "-l", "http://0.0.0.0:3000"]