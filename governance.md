# Governança de Dados — Case Rentcars

## 1. Contexto e metodologia

Os 5 datasets brutos (`raw_partners`, `raw_sessions`, `raw_searches`, `raw_bookings`, `raw_cancellations`) contêm problemas de qualidade **propositais**, conforme aviso do `data_dictionary.md` do case. Este documento consolida os achados de profiling, as regras de negócio do dicionário, e como cada uma foi tratada (ou não) ao longo das camadas staging → intermediate → marts.

Metodologia: profiling inicial de nulos/duplicatas por tabela, seguido de comparação linha a linha entre as "Regras de negócio" declaradas no `data_dictionary.md` e o que estava de fato implementado em cada modelo dbt — essa auditoria revelou uma divergência real entre documentação e código (seção 4).

Testes automatizados (`dbt test`) rodam com dois níveis de severidade: **error** para regras que devem sempre valer no dado final (ex: unicidade em intermediate/marts) e **warn** para achados de qualidade conhecidos, propositais, que são medidos mas não bloqueiam o pipeline (ex: duplicatas em staging, antes do dedup).

## 2. Duplicatas encontradas (staging, antes do dedup)

| Tabela | Linhas totais | Duplicatas de PK | % |
|---|---|---|---|
| `raw_partners` | 22 | 2 | ~9% |
| `raw_sessions` | 120.350 | 342 | ~0,3% |
| `raw_searches` | 80.240 | 236 | ~0,3% |
| `raw_bookings` | 18.124 | 118 | ~0,7% |
| `raw_cancellations` | 4.410 | 79 | ~1,8% |

**Tratamento:** todas deduplicadas na camada `intermediate`, mantendo o registro mais recente por chave (critério de recência: `updated_at`/`created_at` para partners, `started_at` para sessions, `searched_at` para searches, `booked_at` para bookings, `cancelled_at` para cancellations). Testes `unique` em `staging/schema.yml` ficam com `severity: warn` propositalmente — é esperado que staging (1:1 com a fonte, sem lógica de negócio) contenha essas duplicatas; a garantia de unicidade real é cobrada como `error` a partir de `intermediate` em diante.

## 3. Regras de negócio do `data_dictionary.md` × implementação

### raw_partners → int_partners → dim_partners
| Regra | Onde é aplicada | Status |
|---|---|---|
| Somente `status = active` recebe reservas | Filtro (`inner join`) em `int_bookings` | ✅ Aplicada |
| `commission_rate` entre 0.05 e 0.30 | Teste `dbt_expectations` em `dim_partners` | ✅ Testada |
| `partner_id` único | Dedup em `int_partners` + teste `unique` (error) | ✅ Aplicada e testada |

### raw_sessions → int_sessions → fct_sessions
| Regra | Onde é aplicada | Status |
|---|---|---|
| `is_bot = true` excluído das análises | Filtro em `int_sessions` | ✅ Aplicada |
| `ended_at` posterior a `started_at` | Teste `dbt_expectations` (warn) em `int_sessions` | ✅ Testada — **0 violações encontradas**, regra sempre válida nos dados |
| "Nem todo bot está marcado na flag" | Detecção heurística (>50 buscas/5min) | Tratada no Desafio 2 (Q4), não em modelo dbt |

### raw_searches → int_searches → (consumida em Q1/Q4 do D2)
| Regra | Onde é aplicada | Status |
|---|---|---|
| `search_id` único | Dedup em `int_searches` + teste `unique` (error) | ✅ Aplicada e testada |
| Buscas de sessão `is_bot=true` descartadas | Join com `int_sessions` (não mais `stg_sessions`) | ✅ Corrigida — **gap encontrado e corrigido**: a versão inicial usava `stg_sessions`, que não filtra bot |
| `partner_id_clicked` deve existir em `raw_partners` | Teste `relationships` (warn) contra `int_partners` | ✅ Testada — **0 violações encontradas** |
| `dropoff_date >= pickup_date` | Teste `dbt_expectations` (warn) em `int_searches` | ⚠️ Testada — **739 violações** (~0,9% de 80.240 buscas têm `dropoff_date` anterior a `pickup_date`). Mantidas na tabela (não filtradas), sinalizadas apenas via teste — decisão: não descartar por ser um campo de intenção de busca, não uma transação financeira |

### raw_bookings → int_bookings → fct_bookings
| Regra | Onde é aplicada | Status |
|---|---|---|
| `booking_id` único | Dedup em `int_bookings` + teste `unique` (error) | ✅ Aplicada e testada |
| `total_amount > 0` para `confirmed`/`completed` | Filtro em `int_bookings` | ✅ Aplicada (contagem exata de linhas removidas por este filtro ainda não quantificada — pendente) |
| `dropoff_date` posterior a `pickup_date` | Teste `dbt_expectations` (warn) em `int_bookings` | ✅ Testada — **0 violações encontradas** |
| `partner_id` existe e ativo em `raw_partners` | Filtro (`inner join` com parceiros ativos) em `int_bookings` | ✅ Aplicada (reservas de parceiro inativo/inexistente são excluídas do fato, não apenas flagadas — decisão de modelagem) |
| Deduplicar antes de agregação financeira | Dedup em `int_bookings` | ✅ Aplicada |
| Múltiplas reservas mesmo usuário/dia = possível fraude | — | ⚠️ Não tratada — candidata a investigação ad-hoc, fora do escopo do D1 |

### raw_cancellations → int_cancellations
| Regra | Onde é aplicada | Status |
|---|---|---|
| `cancellation_id` único | Dedup em `int_cancellations` + teste `unique` (error) | ✅ Aplicada e testada |
| `booking_id` existe em `raw_bookings` | Filtro (`inner join`) em `int_cancellations` | ✅ Aplicada |
| `refund_amount` não excede `total_amount` da reserva | Filtro em `int_cancellations` | ✅ Aplicada — **ver achado abaixo (seção 4)**; contagem exata de linhas removidas ainda não quantificada — pendente |
| `days_before_pickup` negativo = cancelamento tardio | — | ⚠️ Não tratada — candidata a teste/flag futuro, fora do escopo do D1 |

## 4. Achado: divergência entre documentação e implementação

Durante a revisão cruzada com o `data_dictionary.md`, encontramos que o `schema.yml` de `int_cancellations` **já descrevia** a regra "`refund_amount` não deve exceder o `total_amount` da reserva associada" — mas o SQL do modelo nunca implementava essa validação (o `total_amount` da reserva nem era trazido para a query). Ou seja: a regra estava documentada, mas não codificada. Corrigido trazendo `total_amount` de `stg_bookings` para dentro do modelo e filtrando `refund_amount is null or refund_amount <= booking_total_amount`.

Esse tipo de divergência é exatamente o que este processo de auditoria (documentação × código, tabela por tabela) foi desenhado para pegar antes da entrega final.

## 5. Desafio 2 — decisões e validações por query

### Q1 — Funil sessão → busca → reserva, por país e device

Premissas confirmadas em 09/09/2026:
- Base de sessões: `int_sessions` (não-bot, deduplicada).
- Conversão para "busca": sessão presente em `int_searches`.
- Conversão para "reserva": sessão presente em `fct_bookings` **e** cujo `booking_id` não aparece em `int_cancellations` — reservas canceladas não contam como conversão real, mesmo já tendo passado por todas as regras de `raw_bookings`.
- País e device herdados da sessão de origem (únicos lugares do funil onde esses atributos existem).
- Janela de tempo: período completo disponível nos dados (01/10/2024–31/03/2025), sem recorte.
- `country`/`device` nulos ou em branco viram `'Não identificado'` em vez de serem descartados, para não perder volume do funil.
- Colunas de saída traduzidas para português (`pais`, `dispositivo`) para consumo direto por stakeholders não técnicos.

**Validação:** os resultados foram conferidos de forma independente, reconstruindo a mesma lógica (staging → intermediate → fato) diretamente sobre os CSVs brutos fora do pipeline dbt local — os números bateram exatamente para as 21 combinações de país × device. Taxa de conversão geral (sessão → reserva) girou entre ~8,9% e ~10,2% conforme o segmento, com Brasil concentrando o maior volume absoluto de sessões (BR/desktop: 15.639, BR/mobile: 15.327), como esperado por ser o mercado principal da operação.

## 6. Limitações e itens em aberto

- Contagem exata de linhas removidas pelos filtros de `int_bookings` (total_amount ≤ 0 em confirmed/completed) e `int_cancellations` (refund_amount > total_amount) ainda não foi quantificada — os filtros estão corretos, mas falta medir "antes vs. depois" para reportar volume aqui.
- "Múltiplas reservas do mesmo usuário no mesmo dia" e "`days_before_pickup` negativo" são sinalizados pelo dicionário como possíveis indícios de fraude/anomalia, mas não foram transformados em teste ou flag — ficam como candidatos a uma investigação ad-hoc ou a testes futuros.
- `dim_users` cobre apenas usuários autenticados (com `user_id`); sessões e reservas 100% anônimas não geram linha de dimensão, ficando nos fatos com `user_id` nulo.
