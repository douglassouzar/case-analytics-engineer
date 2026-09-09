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

### Q2 — Top 10 parceiros por volume de reservas nos últimos 90 dias, excluindo cancelamentos

Premissas confirmadas em 09-10/09/2026:
- Janela "últimos 90 dias": `max(booked_at)` de `fct_bookings` como referência de "hoje", já que o dataset não tem uma data corrente real.
- Verificação em duas camadas antes de contar uma reserva: (1) `status in ('confirmed', 'completed')` em `fct_bookings` — segue o glossário do `data_dictionary.md`, que define que reserva só gera receita nesses status; (2) do que sobrou, remove qualquer `booking_id` presente em `int_cancellations` (mesmo critério da Q1, cobre status desatualizado).

**Achado durante a construção (mudou o desenho da query):** ao montar a soma de receita por parceiro, encontramos que os 20 parceiros do dataset têm reservas nas 5 moedas presentes na base (BRL, USD, ARS, CLP, COP) — não é um padrão de "um parceiro, uma moeda". O dataset não inclui nenhuma tabela de taxa de câmbio. Somar `total_amount` entre moedas diferentes sem conversão produz um número financeiramente sem sentido (equivale a somar reais, dólares e pesos como se fossem a mesma unidade).

**Decisão adotada:** a receita não é apresentada como uma única coluna somada. A query abre o valor em uma coluna por moeda (`total_BRL`, `total_USD`, `total_ARS`, `total_CLP`, `total_COP`), sem conversão. O ranking de "top 10" passa a usar `quantidade_reservas` (volume, métrica comparável entre parceiros independente de moeda) como critério principal, com empate desempatado por `total_BRL` — BRL assumido como moeda do mercado principal da operação, por ser o país de origem da Rentcars no case.

**Solicitação de dado externo para uma próxima iteração:** para reportar receita real convertida (em vez de aberta por moeda), seria necessário incorporar uma tabela de taxas de câmbio históricas cobrindo o período 01/10/2024–31/03/2025 para BRL/USD/ARS/CLP/COP. O Banco Central do Brasil disponibiliza isso publicamente e de graça: dataset **"Taxas de Câmbio — todos os boletins diários"** no Portal de Dados Abertos do BCB (`dadosabertos.bcb.gov.br`), com API OData filtrável por período e moeda, exportável em CSV — cobre as 5 moedas encontradas nesta base. Ver: https://dadosabertos.bcb.gov.br/dataset/taxas-de-cambio-todos-os-boletins-diarios/resource/0439af6a-d9be-4bf7-bf1a-60583e5f4c1c

### Q3 — LTV médio por cohort de primeiro acesso (mês/ano)

Premissas confirmadas em 10/09/2026:
- LTV = receita acumulada por usuário dentro do período disponível nos dados (aproximação de "valor gerado até aqui", não o ciclo de vida completo do cliente — o dataset cobre só 6 meses). Não é contagem de sessões nem tempo até reservar.
- Mesma regra de validade de receita da Q2 (duas camadas: `status in ('confirmed','completed')` + fora de `int_cancellations`), mas **sem** corte de 90 dias — soma o período inteiro disponível.
- Aberto por moeda pelo mesmo motivo da Q2 (sem tabela de câmbio disponível).
- Cohort = mês/ano de `first_seen_at` (primeira sessão) em `dim_users`.
- Métrica reportada é a média de LTV por usuário na cohort, com denominador = **todos** os usuários da cohort (inclusive os que nunca reservaram, contados como LTV = 0) — reflete o valor médio real gerado pela cohort inteira, não só pelos pagantes.

**Achado:** de 37.891 usuários em `dim_users`, **926 (2,4%) têm `first_seen_at` nulo** — ou seja, aparecem em reservas (`fct_bookings`) mas nunca tiveram uma sessão válida registrada em `int_sessions` (nem mesmo antes da exclusão de bots). Esses usuários ficam de fora da análise de cohort por não terem um mês/ano de primeiro acesso para agrupar. Candidato a investigação: pode ser reserva feita fora do funil rastreado (ex: canal offline/parceiro) ou lacuna de instrumentação de sessão.

**Resultado:** 6 coortes mensais (2024-10 a 2025-03), com volume de usuários decrescente nas coortes mais recentes — padrão esperado, já que coortes recentes tiveram menos tempo dentro da janela de dados para acumular reservas.

### Q4 — Detecção de sessões suspeitas de bot (>50 buscas em janela de 5 min)

Premissas confirmadas em 10/09/2026:
- Base: `stg_searches` + `stg_sessions` (staging, sem o filtro de `is_bot` que já existe em `int_searches`/`int_sessions`) — de propósito, para poder comparar o achado por volume contra a flag `is_bot` já existente.
- Janela **fixa** de 5 minutos (não deslizante) — escolhida por simplicidade/menor complexidade de query. Validamos que essa simplificação não muda o resultado neste dataset (a 2ª sessão com mais buscas no total tem só 7, longe do limiar de 50 — não há rajada real na borda de um bloco que a janela fixa deixaria escapar).

**Achado:** apenas **1 sessão** em todo o dataset ultrapassa 50 buscas numa janela de 5 minutos (68 buscas concentradas), e essa sessão **não estava marcada como `is_bot = True`** — exatamente o caso que o `data_dictionary.md` avisa ("nem todo comportamento automatizado está necessariamente marcado nessa flag"). Ou seja: a flag `is_bot` do dataset tem 0 falsos negativos capturados por volume de busca neste teste específico, com exceção dessa 1 sessão que passou despercebida.

## 6. Limitações e itens em aberto

- Contagem exata de linhas removidas pelos filtros de `int_bookings` (total_amount ≤ 0 em confirmed/completed) e `int_cancellations` (refund_amount > total_amount) ainda não foi quantificada — os filtros estão corretos, mas falta medir "antes vs. depois" para reportar volume aqui.
- "Múltiplas reservas do mesmo usuário no mesmo dia" e "`days_before_pickup` negativo" são sinalizados pelo dicionário como possíveis indícios de fraude/anomalia, mas não foram transformados em teste ou flag — ficam como candidatos a uma investigação ad-hoc ou a testes futuros.
- `dim_users` cobre apenas usuários autenticados (com `user_id`); sessões e reservas 100% anônimas não geram linha de dimensão, ficando nos fatos com `user_id` nulo.
