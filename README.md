# 🧘 Rinha de Backend 2025 

Resolvi desenvolver esse backend com uma linguagem que eu uso no dia a dia e sei que não é mais tão popular hoje em dia, então queria ver o que eu era capaz de fazer com as restrições física de máquina e um bom e velho Mojolicious
## 🚀 Tecnologias 

**- Linguagem:** Perl
**- Framework:** Mojolicious
**- Mensageria:** Redis
**- Banco de da Dados:** PostgreSQL
**- Load balancer:** NGNIX
**- Orquestração:** Docker + Docker Compose


## ♟️ Estratégia

Dois workers, um pra sempre verificar a cada 5 segundos, decidir qual é o melhor serviço de pagamento e postar no redis. Outro worker para fazer o processamento das requests POST para adicionar um pagamento.

## Link do Repo

[Repositório do Github](https://github.com/GaNardelli/rinha-backend-2025-mojolicius)