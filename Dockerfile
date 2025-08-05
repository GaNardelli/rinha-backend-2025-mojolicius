FROM perl:5.36-slim AS builder

WORKDIR /opt

# Instala dependências do sistema e Perl em uma única camada
RUN apt-get update && apt-get install -y \
    libssl-dev libexpat1-dev libz-dev libpq-dev build-essential \
    && cpanm -n Mojolicious Mojo::Redis Mojo::UserAgent Mojo::Pg JSON DateTime \
    && apt-get remove -y build-essential \
    && apt-get autoremove -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/* ~/.cpanm

# Copia o restante do projeto
COPY . .

EXPOSE 3000

CMD ["morbo", "./scripts/PaymentHandler"]