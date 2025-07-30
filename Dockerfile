FROM debian:bookworm-slim

WORKDIR /opt/

COPY . .

RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libexpat1-dev \
    libz-dev \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN cpan App::cpanminus

RUN cpanm --no-test Mojolicious Mojo::Redis Mojo::UserAgent Mojo::IOLoop JSON Mojo::Pg DateTime

EXPOSE 3000

CMD ["morbo", "./scripts/PaymentHandler"]