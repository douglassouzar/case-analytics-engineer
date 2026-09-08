# Case Rentcars

Projeto de modelagem de dados do Case Técnico Senior Analytics Engineer Sênior, com a inclusão das camadas staging, camada intermediária e marts para os domínios de sessões, buscas, reservas, cancelamentos e parceiros.

## Como executar o projeto.

Pré-requisitos: Python 3.9–3.12 e Git instalados.

```executar no powershell windows
git clone https://github.com/douglassouzar/case-ae-rentcars.git
cd repo-case-ae-rentcars\dbt\rentcars_analytics

python -m venv ..\..\venv
..\..\venv\Scripts\Activate.ps1

pip install dbt-duckdb
dbt deps           # instala o pacote dbt_expectations (packages.yml)
dbt debug          # valida conexão com o DuckDB local
dbt run            # materializa staging, intermediate e marts
dbt test           # roda os testes nativos e customizados
dbt docs generate && dbt docs serve   # documentação navegável (opcional)
```

Os 5 arquivos `.csv` de origem ficam em `data/` dentro deste projeto e são lidos diretamente pelo dbt-duckdb via `external_location` (ver `models/staging/sources.yml`), não é necessário criar um schema ou subir dados manualmente antes de rodar.

## Como executar o projeto.

data/*.csv (raw)
│
▼
[ staging ] stg_partners, stg_sessions, stg_searches, stg_bookings, stg_cancellations
│ (1:1 com o source — cast de tipos, trim, lower/upper em categóricos)
▼
[ intermediate ] int_sessions_deduped, int_bookings_valid, int_cancellations_valid
│ (deduplicação por chave, regras de negócio, filtro de bot,
│ validação de parceiro ativo, total_amount, refund_amount)
▼
[ marts ] dim_partners, dim_users, fct_bookings (incremental), fct_sessions (incremental).

## Descrição de modelagem

- **Ambiente**: dbt-duckdb local em vez de um warehouse cloud (Snowflake/BigQuery/Athena), permitindo rodar o projeto ponta-a-ponta sem depender de credenciais ou provisionamento externo, mantendo a mesma estrutura de camadas (staging/intermediate/marts) que seria usada em produção.

- **Staging não remove duplicatas**: a staging só ajusta os formato (tipos, trim, case); duplicatas e regras de negócio ficam explícitas na camada intermediate, para que a decisão de deduplicação seja rastreável.

- **Critério de deduplicação**: em todas as entidades com duplicata (`sessions`, `bookings`, `cancellations`, `partners`), o critério foi manter o registro mais recente pela coluna de timestamp mais relevante (`started_at`, `booked_at`, `cancelled_at`, `updated_at`/`created_at`). Critério simples e auditável outras alternativas não foram avaliadas em tempo.

- **`dim_users` inclui apenas usuários autenticados** vistos em sessões ou reservas em que `user_id` é não nulo. Sessões/reservas anônimas continuam nos fatos, com `user_id` nulo.

- **Modelos incrementais** (`fct_bookings`, `fct_sessions`): estratégia `delete+insert` por chave única (`booking_id`, `session_id`), filtrando por data máxima já processada, evitando reprocessar o histórico inteiro a cada execução.

- **Testes customizados**: usados `dbt_expectations.expect_column_values_to_be_between` para validar `commission_rate` (0.05–0.30) e `total_amount` onde é > 0 para reservas confirmed/completed, regras informadas no dicionário de dados.

## Limitações conhecidas / próximos passos

- `int_cancellations_valid` não valida `refund_status` cruzado com `refund_amount` (ex: `refund_status = 'denied'` com `refund_amount` preenchido), não está como regra explícita do dicionário, mas seria um ponto de checagem posterior.

- A heurística de bot mencionada no dicionário ("nem todo comportamento automatizado está necessariamente marcado na flag is_bot") não foi implementada na camada intermediate, será aplicada na query Q4 do SQL, que trata de detecção de sessões suspeitas.

- Não foi criado um modelo `int_searches`, os marts mínimos exigidos não dependem dele, pode ser criado futuramente para suportar análises de funil com mais profundidade.

- `dim_users` não tem uma dimensão de fallback para sessões/reservas anônimas, ficou como nulo direto nos fatos.