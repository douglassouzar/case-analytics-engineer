# Case Técnico — Rentcars | Senior Analytics Engineer

Repositório de resolução do case técnico para a vaga de Senior Analytics Engineer na Rentcars, estruturado em 5 desafios avaliados com pesos diferentes.

> Critério de priorização adotado ao longo do case: a própria orientação do case, "um dbt incremental bem documentado + um discovery com data contract completo valem mais que 5 desafios superficiais", foi usada como critério de desempate sob restrição de tempo — por isso D1 e D5 receberam o maior cuidado.

| Desafio | Peso | Pasta | Status |
|---|---|---|---|
| D1 — Modelagem com dbt | 25% | `dbt/rentcars_analytics/` | ✅ Concluído |
| D2 — SQL analítico | 20% | `sql/` | ✅ Concluído |
| D3 — Dashboard | 20% | `dashboard/` | ⏳ Pendente — ver seção "Status do D3" abaixo |
| D4 — Governança de dados | 20% | `governance.md` | ✅ Concluído |
| D5 — Comunicação com stakeholders | 15% | `stakeholders/` | ✅ Concluído |

---

## Status do D3 (Dashboard)

Por restrição de tempo, a construção visual do dashboard do Desafio 3 não foi concluída até o prazo de entrega inicial (10/09, manhã). Os dados que o alimentariam já estão prontos e testados nas camadas `marts` do Desafio 1 e nos resultados de `sql/results/` do Desafio 2 falta apenas a camada de visualização.

**Compromisso:** o D3 será entregue como atualização deste repositório até **14/09/2026**.

---

## Como executar o projeto dbt do zero

### Pré-requisitos

- Python 3.9 a 3.12 (faixa suportada pelo `dbt-duckdb` no momento deste case)
- Git

### Passo a passo

```bash
# 1. Clonar/entrar no repositório
cd repo-case-ae-rentcars/dbt/rentcars_analytics

# 2. Criar e ativar o ambiente virtual
python -m venv venv
source venv/bin/activate        # Windows PowerShell: .\venv\Scripts\Activate.ps1
                                 # Windows cmd:        venv\Scripts\activate.bat

# 3. Instalar o dbt
python -m pip install --upgrade pip
pip install dbt-duckdb

# 4. Instalar os pacotes dbt (dbt_expectations), declarados em packages.yml
dbt deps

# 5. Configurar o profiles.yml (normalmente em ~/.dbt/profiles.yml)
#    conteúdo abaixo — ajuste o path se for rodar de outro diretório
```

`profiles.yml`:
```yaml
rentcars_analytics:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: 'rentcars.duckdb'
      threads: 4
```

```bash
# 6. Validar a conexão
dbt debug

# 7. Rodar o projeto
dbt run                 # 1ª execução: carga full de tudo
dbt run                 # 2ª execução em diante: incremental nos fatos (fct_bookings, fct_sessions)
dbt run --full-refresh  # força reprocessamento completo quando necessário

# 8. Rodar os testes (genéricos + dbt_expectations + testes singulares)
dbt test

# 9. Gerar e navegar a documentação
dbt docs generate && dbt docs serve
```

**Nota sobre os dados de origem:** os 5 CSVs (`raw_partners`, `raw_sessions`, `raw_searches`, `raw_bookings`, `raw_cancellations`) devem estar em `dbt/rentcars_analytics/data/`. O projeto os lê via `external_location` em `models/staging/sources.yml`, simulando tabelas de um warehouse sem precisar carregá-los manualmente antes — ver "Limitações conhecidas" sobre essa escolha de ambiente.

---

## Diagrama de arquitetura do modelo de dados

```
                         ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  ┌──────────────────┐  ┌────────────────────────┐
   FONTE (CSV)           │  raw_partners    │  │  raw_sessions    │  │  raw_searches      │  │  raw_bookings    │  │  raw_cancellations     │
                         └────────┬─────────┘  └────────┬─────────┘  └─────────┬──────────┘  └────────┬─────────┘  └───────────┬────────────┘
                                  │                      │                      │                      │                        │
                                  ▼                      ▼                      ▼                      ▼                        ▼
   STAGING                 stg_partners            stg_sessions           stg_searches            stg_bookings           stg_cancellations
   (1:1 c/ fonte,          renomeia, tipa,          renomeia, tipa,        renomeia, tipa,          renomeia, tipa,        renomeia, tipa,
    sem regra de           normaliza texto          normaliza texto        normaliza texto          normaliza texto        normaliza texto
    negócio)               (status)                 (device, country)     (car_category)           (car_category, etc.)   (—)
                                  │                      │                      │                      │                        │
                                  │                      ▼                      │                      │                        │
                                  │                int_sessions ◄───────────────┤                      │                        │
                                  │                (exclui is_bot,              │                      │                        │
                                  │                 dedup session_id)           │                      │                        │
                                  │                      │                      ▼                      │                        │
                                  │                      │                int_searches                 │                        │
                                  │                      │                (dedup search_id,             │                        │
                                  │                      │                 restrito a sessão            │                        │
                                  │                      │                 válida/não-bot)               │                        │
                                  ▼                      │                                              ▼                        │
                            int_partners                 │                                        int_bookings ◄─────────────────┤
                            (dedup partner_id,            │                                        (restrito a parceiro           │
                             mais recente por              │                                        active, dedup booking_id,      │
                             updated_at/created_at)        │                                        total_amount>0 p/              │
                                  │                        │                                        confirmed/completed)           │
                                  │                        │                                              │                        ▼
                                  │                        │                                              │                  int_cancellations
                                  │                        │                                              │                  (dedup cancellation_id,
                                  │                        │                                              │                   restrito a booking
                                  │                        │                                              │                   existente, refund_amount
                                  │                        │                                              │                   <= total_amount)
                                  ▼                        ▼                                              ▼
   MARTS                   dim_partners              fct_sessions                                  fct_bookings
   (star schema,           1 linha/partner_id        1 linha/session_id                             1 linha/booking_id
    consumido              grão: cadastro            incremental (delete+insert                     incremental (delete+insert
    por BI/D2/D3)          de parceiro               por started_at)                                por booked_at)
                                  │                        │                                              │
                                  │                        └──────────────┬───────────────────────────────┘
                                  │                                       ▼
                                  │                                 dim_users
                                  │                                 (union de user_id distintos vistos
                                  │                                  em int_sessions ∪ int_bookings;
                                  │                                  first_seen_at = min(started_at))
                                  │
                                  └── consumido também por int_bookings (filtro de parceiro ativo)
```

Legenda: setas verticais = linhagem direta (staging → intermediate → marts); a seta de `int_cancellations` para `int_bookings` representa o uso cruzado de `total_amount` da reserva para validar `refund_amount`, não uma dependência de carga.

---

## Justificativa das principais decisões de modelagem e materialização

**dbt-duckdb em vez de um warehouse cloud (Snowflake/BigQuery/Athena).** DuckDB roda localmente sem provisionamento, sem custo e sem esperar criação de conta — prioriza velocidade de setup e reprodutibilidade para quem for avaliar o case, sem abrir mão de testes, incrementalidade e documentação. Os mesmos conceitos aplicados aqui valem para qualquer warehouse.

**Arquitetura em 3 camadas (staging → intermediate → marts).** Staging fica estritamente 1:1 com a fonte (renomeação, tipagem, normalização de texto), sem nenhuma regra de negócio — isso permite que os testes de unicidade em staging rodem como `severity: warn` (duplicata é esperada ali) e só se tornem bloqueantes (`severity: error`) a partir de intermediate, onde a deduplicação já foi aplicada. Intermediate concentra toda a lógica de negócio e limpeza pesada (deduplicação, filtros de validade, cruzamento entre tabelas), para que os marts finais fiquem simples de ler e de auditar.

**Star schema mínimo nos marts (`dim_partners`, `dim_users`, `fct_bookings`, `fct_sessions`).** Escolhido por ser o padrão mais direto de consumo para BI/análise (D2 e D3 partem diretamente desses 4 modelos), sem introduzir dimensões que os dados não sustentam — por exemplo, não foi criada uma dimensão de tempo separada porque os fatos já carregam timestamps completos e o volume (dezenas de milhares de linhas) não justifica esse grau de normalização adicional.

**`dim_users` cobre apenas usuários autenticados.** Sessões e reservas 100% anônimas (sem `user_id`) não geram linha de dimensão — decisão para evitar um grão ambíguo do tipo "usuário anônimo genérico" que misturaria pessoas diferentes sob um mesmo identificador. Essas sessões/reservas continuam existindo nos fatos, só com `user_id` nulo.

**`fct_bookings` e `fct_sessions` como incremental (`delete+insert`).** Ambos os fatos crescem por append ao longo do tempo (nova reserva, nova sessão) e não sofrem update retroativo de linhas antigas nesse dataset — o padrão `delete+insert` filtrando por `booked_at`/`started_at` mais recente que o já carregado evita reprocessar o histórico inteiro a cada rodada, sem o risco de duplicar linha que a estratégia `append` teria se o pipeline rodasse mais de uma vez sobre a mesma janela. `dim_partners` e `dim_users` foram deixados como `table` (full refresh) por serem pequenos (22 parceiros, ~38 mil usuários) e não terem regra de particionamento temporal natural.

**Duas camadas de verificação de receita (status + ausência de cancelamento) repetidas em D1/D2/D5.** `fct_bookings` já filtra por regras de validade (parceiro ativo, valor positivo), mas o status de uma reserva no sistema de origem pode não ter sido atualizado no momento do cancelamento — por isso toda métrica de receita neste projeto (D2 Q2/Q3, D5) sempre cruza `fct_bookings` com `int_cancellations`, em vez de confiar só no campo `status`.

**Receita nunca somada entre moedas.** O dataset tem reservas em 5 moedas (BRL, USD, ARS, CLP, COP) sem tabela de câmbio. Em vez de inventar uma taxa de conversão, toda métrica de receita é reportada aberta por moeda — decisão levada ao extremo no D5, onde o próprio discovery com a stakeholder de Revenue/Pricing gira em torno desse ponto (ver `stakeholders/roteiro_entrevista.md`).

**Severidade de teste como sinal, não como bloqueio.** Achados de qualidade propositais do case (categoria `compact` fora do domínio, sessões longas, cliques sem resultado, etc.) usam `severity: warn` com threshold documentado em `governance.md` — para não travar o pipeline por um padrão de dado que já se sabe existir, mas ainda assim ficar visível e quantificado a cada `dbt test`.

---

## Limitações conhecidas e melhorias que implementaria com mais tempo

- **Ambiente local (DuckDB) em vez de warehouse cloud real**, por restrição de tempo — os sources apontam para CSVs via `external_location` em vez de tabelas já carregadas em um DW. Com mais tempo, subiria os CSVs para um Snowflake/BigQuery de teste e usaria os mesmos modelos, só trocando o adapter.
- **Sem tabela de câmbio.** Toda métrica de receita fica aberta por moeda. Próximo passo natural: incorporar a cotação histórica diária do Banco Central do Brasil (`dadosabertos.bcb.gov.br`, dataset "Taxas de Câmbio, todos os boletins diários"), cobrindo as 5 moedas do dataset, com decisão pendente sobre qual data de referência usar na conversão.
- **Receita bruta, não líquida de reembolso.** `fct_bookings.total_amount` não desconta `refund_amount` de reembolsos parciais. Levantado no discovery do D5 como fase 2: exigiria um novo modelo intermediate combinando `fct_bookings` com `int_cancellations`.
- **Modelos órfãos removidos do repositório:** `int_bookings_valid.sql`, `int_sessions_deduped.sql` e `int_cancellations_valid.sql` eram versões antigas, não referenciadas em nenhum lugar (resíduo de uma renomeação para `int_bookings`, `int_sessions`, `int_cancellations`). Removidos na revisão final para não deixar código morto no repositório de entrega.
- **Múltiplas reservas do mesmo usuário no mesmo dia** e **outliers de valor por categoria** ficam monitorados via teste `severity: warn`, não bloqueados — são candidatos a fraude/anomalia, não certezas, e exigem revisão humana antes de qualquer exclusão automática (ver `governance.md` seções 3 e 8).
- **SLA de dados (`governance.md` seção 8) é uma proposta de threshold, não um gate de CI automatizado.** Próximo passo natural: `dbt build` rodando em CI (Buildkite/GitHub Actions) a cada PR, bloqueando merge se algum teste `severity: error` falhar ou se um `warn` ultrapassar o threshold da tabela de SLA.
- **Retenção de dado pessoal (`user_id`) sem política numérica definida** — registrado como gap explícito em `governance.md` seção 9.2, não uma lacuna escondida.
- **D3 (Dashboard) pendente**, ver seção "Status do D3" acima — compromisso de entrega até 14/09/2026.

---

## Estrutura do repositório

```
repo-case-ae-rentcars/
├── dbt/rentcars_analytics/    ← Desafio 1: projeto dbt completo (staging → intermediate → marts, testes, docs)
├── sql/                        ← Desafio 2: queries analíticas + scripts de execução/exportação em CSV
├── dashboard/                  ← Desafio 3: pendente, ver "Status do D3"
├── governance.md               ← Desafio 4: qualidade de dado, catálogo, glossário de métricas, SLA, política de PII
├── stakeholders/                ← Desafio 5: discovery simulado, requisitos técnicos e data contract
│   ├── roteiro_entrevista.md
│   ├── requisitos_tecnicos.md
│   └── data_contract.yaml
└── README.md                   ← este arquivo
```
