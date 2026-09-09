# Governança de Dados — Case Rentcars

## 1. Contexto e metodologia

Os 5 datasets brutos (`raw_partners`, `raw_sessions`, `raw_searches`, `raw_bookings`, `raw_cancellations`) vêm com problemas de qualidade **de propósito**, como o próprio `data_dictionary.md` do case avisa. Este documento junta o que encontramos no profiling, as regras de negócio descritas no dicionário, e o que fizemos (ou decidimos não fazer, e por quê) com cada uma delas ao longo das camadas staging → intermediate → marts.

Como chegamos até aqui: primeiro um profiling de nulos/duplicatas tabela por tabela, depois uma comparação linha a linha entre as "Regras de negócio" do `data_dictionary.md` e o que estava de fato implementado em cada modelo dbt — essa auditoria pegou uma divergência real entre documentação e código (seção 4). Por fim, já perto da entrega, fizemos uma segunda varredura mais ampla e sistemática — domínios categóricos, formatos inconsistentes, outliers e regras de negócio que ainda não tinham sido checadas com números — que também achou coisa nova (junto ao longo das seções abaixo, e resumida na seção 4.2).

Os testes automatizados (`dbt test`) rodam em dois níveis de severidade: **error** pras regras que precisam sempre valer no dado final (ex.: unicidade em intermediate/marts) e **warn** pros achados de qualidade conhecidos e propositais, que a gente mede mas não deixa travar o pipeline (ex.: duplicatas em staging, antes do dedup).

## 2. Duplicatas encontradas (staging, antes do dedup)

| Tabela | Linhas totais | Chaves com duplicata | % |
|---|---|---|---|
| `raw_partners` | 22 | 2 | ~9% |
| `raw_sessions` | 120.350 | 342 | ~0,3% |
| `raw_searches` | 80.240 | 236 | ~0,3% |
| `raw_bookings` | 18.124 | 118 | ~0,7% |
| `raw_cancellations` | 4.410 | 79 | ~1,8% |

Conferimos linha a linha: em todos os casos as duplicatas são cópias exatas da mesma linha (mesmo `booking_id`/`session_id`/etc. com todos os outros campos idênticos) — não são versões conflitantes do mesmo registro. Isso simplifica o dedup: não tem "qual versão é a certa", é só remover a cópia.

**Tratamento:** todas deduplicadas na camada `intermediate`, mantendo o registro mais recente por chave (critério de recência: `updated_at`/`created_at` pra partners, `started_at` pra sessions, `searched_at` pra searches, `booked_at` pra bookings, `cancelled_at` pra cancellations). Os testes `unique` em `staging/schema.yml` ficam com `severity: warn` de propósito — é esperado que staging (1:1 com a fonte, sem lógica de negócio) carregue essas duplicatas; a garantia real de unicidade só é cobrada como `error` a partir de `intermediate` em diante.

## 3. Regras de negócio do `data_dictionary.md` × implementação

### raw_partners → int_partners → dim_partners
| Regra | Onde é aplicada | Status |
|---|---|---|
| Somente `status = active` recebe reservas | Filtro (`inner join`) em `int_bookings` | ✅ Aplicada |
| `commission_rate` entre 0.05 e 0.30 | Teste `dbt_expectations` em `dim_partners` | ✅ Testada — 0 violações nos 22 parceiros |
| `partner_id` único | Dedup em `int_partners` + teste `unique` (error) | ✅ Aplicada e testada |

**Achados extras (não são regras do dicionário, mas apareceram no profiling):**
- `status` chega com 3 formatos diferentes (`active`, `Active`, `inactive`) — o `stg_partners` já normaliza com `lower(trim())`, então o filtro de `status = active` funciona certo mesmo assim. Só registrando porque, sem essa normalização, os 2 parceiros gravados como `Active` (maiúsculo) cairiam fora do filtro por engano.
- `country`: o dicionário descreve 3% de nulo esperado nessa coluna, mas os dados reais não têm nenhum nulo (0%). É só uma divergência entre o que o dicionário descreve e o dado real — não afeta nada no pipeline, mas vale registrar.

### raw_sessions → int_sessions → fct_sessions
| Regra | Onde é aplicada | Status |
|---|---|---|
| `is_bot = true` excluído das análises | Filtro em `int_sessions` | ✅ Aplicada |
| `ended_at` posterior a `started_at` | Teste `dbt_expectations` (warn) em `int_sessions` | ✅ Testada — **0 violações**, a regra vale sempre nos dados |
| "Nem todo bot está marcado na flag" | Detecção heurística (>50 buscas/5min) | Tratada no Desafio 2 (Q4), não em modelo dbt |

**Achados extras:**
- `device` e `country` chegam com formatação inconsistente (`DESKTOP`/`desktop`, `Mobile`/`mobile`, `BR`/`br`/`Br`) — de novo, já normalizado em staging (`lower(trim())` pra device, `upper(trim())` pra country), então o funil da Q1 não fica distorcido. Sem essa normalização, o Brasil apareceria fatiado em 3 países diferentes no resultado.
- **589 sessões com duração acima de 6 horas** (a mais longa chega a quase 72h). O dicionário diz que "sessões são encerradas após 30 min de inatividade" e que a duração típica não passa de algumas horas — então essas sessões longas contrariam essa expectativa na prática. Não filtramos nem flagamos isso em nenhum modelo por enquanto; fica como candidato a investigação (pode ser bug no cálculo de `ended_at`, sessão que nunca fechou, ou outro padrão de bot que passou batido pela flag `is_bot`).

### raw_searches → int_searches → (consumida em Q1/Q4 do D2)
| Regra | Onde é aplicada | Status |
|---|---|---|
| `search_id` único | Dedup em `int_searches` + teste `unique` (error) | ✅ Aplicada e testada |
| Buscas de sessão `is_bot=true` descartadas | Join com `int_sessions` (não mais `stg_sessions`) | ✅ Corrigida — **gap encontrado e corrigido**: a versão inicial usava `stg_sessions`, que não filtra bot |
| `partner_id_clicked` deve existir em `raw_partners` | Teste `relationships` (warn) contra `int_partners` | ✅ Testada — **0 violações** |
| `dropoff_date >= pickup_date` | Teste `dbt_expectations` (warn) em `int_searches` | ⚠️ Testada — **739 violações** (~0,9% de 80.240 buscas têm `dropoff_date` antes de `pickup_date`, já contando com dedup). Mantidas na tabela, só sinalizadas via teste — decisão: não descartar, porque é um campo de intenção de busca, não uma transação financeira |

**Achados extras:**
- `car_category`: além das 5 categorias do domínio canônico do dicionário (`economy, suv, luxury, pickup, minivan`), aparece uma 6ª — `compact` — tanto em `raw_searches` quanto em `raw_bookings`. Não é erro de formatação (já vem em minúsculo, sem espaço extra); é uma categoria a mais que o dicionário não previa. Staging normaliza texto mas não valida contra a lista esperada, então `compact` passa direto pra frente sem ser barrada nem sinalizada — vale considerar um teste `accepted_values` pra isso.
- **1.197 buscas** têm `partner_id_clicked` preenchido mas `num_results = 0` — ou seja, o usuário "clicou" num parceiro num resultado que, segundo o dado, não deveria ter aparecido. É uma inconsistência lógica entre duas colunas da mesma linha, não coberta por nenhuma regra do dicionário. Não tratamos isso em modelo nenhum; fica como achado pra investigação futura (pode ser problema de instrumentação do evento de clique).

### raw_bookings → int_bookings → fct_bookings
| Regra | Onde é aplicada | Status |
|---|---|---|
| `booking_id` único | Dedup em `int_bookings` + teste `unique` (error) | ✅ Aplicada e testada |
| `total_amount > 0` para `confirmed`/`completed` | Filtro em `int_bookings` | ✅ Aplicada — **156 reservas** removidas por esse filtro (incluindo valores negativos, o menor sendo -R$484,89, e reservas com `total_amount = 0`); mais **297 reservas** `confirmed`/`completed` com `total_amount` nulo também ficam fora |
| Valores de `total_amount` muito acima do padrão da categoria devem ser investigados | — | ⚠️ Não tratada em modelo — ver achado abaixo |
| `dropoff_date` posterior a `pickup_date` | Teste `dbt_expectations` (warn) em `int_bookings` | ✅ Testada — **0 violações** |
| `partner_id` existe e ativo em `raw_partners` | Filtro (`inner join` com parceiros ativos) em `int_bookings` | ✅ Aplicada (reservas de parceiro inativo/inexistente são excluídas do fato, não só flagadas — decisão de modelagem) |
| Deduplicar antes de agregação financeira | Dedup em `int_bookings` | ✅ Aplicada |
| Múltiplas reservas mesmo usuário/dia = possível fraude | — | ⚠️ Não tratada — **16 usuários com 34 reservas** no total caem nesse padrão (um caso chega a 4 reservas do mesmo usuário no mesmo dia). Candidata a investigação ad-hoc, fora do escopo do D1 |

**Achado quantificado — outliers de `total_amount` por categoria:** rodamos IQR (1.5×) sobre `total_amount` de reservas `confirmed`/`completed`, dedupicadas, separando por `car_category`. Deu ~101 outliers no total espalhados pelas 7 categorias (incluindo `compact` e nulo). Os casos mais chamativos: `pickup` (22 outliers, limite superior ~R$7.901, máximo encontrado R$79.311 — 10x o limite) e `economy` (9 outliers, limite ~R$7.953, máximo R$77.361). Isso responde diretamente à regra do dicionário sobre "valores muito acima do padrão da categoria" — que até então não tinha nenhuma checagem associada. Não implementamos filtro nem flag em modelo por enquanto; é um bom candidato a teste `dbt_expectations` (tipo `expect_column_values_to_be_between` com limite por categoria, ou uma coluna calculada `is_outlier`).

**Também vale registrar:** `total_amount` negativo aparece em **178 reservas no total**, não só nas `confirmed`/`completed` — ou seja, o problema não é exclusivo do filtro de receita, é um padrão mais amplo no dado bruto.

### raw_cancellations → int_cancellations
| Regra | Onde é aplicada | Status |
|---|---|---|
| `cancellation_id` único | Dedup em `int_cancellations` + teste `unique` (error) | ✅ Aplicada e testada |
| `booking_id` existe em `raw_bookings` | Filtro (`inner join`) em `int_cancellations` | ✅ Aplicada |
| Reserva tem no máximo 1 cancelamento associado | Consequência natural do dedup por `booking_id` | ✅ Conferida — depois do dedup, **0 reservas** têm mais de um cancelamento. As 80 ocorrências que apareceram numa primeira olhada eram só efeito das linhas duplicadas do raw, não cancelamentos reais em duplicidade |
| `refund_amount` não excede `total_amount` da reserva | Filtro em `int_cancellations` | ✅ Aplicada — **794 cancelamentos** removidos por esse filtro (contagem que antes estava pendente — ver seção 4) |
| `days_before_pickup` negativo = cancelamento tardio | — | ⚠️ Não tratada — **93 cancelamentos** com `days_before_pickup` negativo (o pior caso é -2 dias). Candidata a teste/flag futuro, fora do escopo do D1 |

## 4. Achados de auditoria (documentação × implementação, e um bug no pipeline)

### 4.1 — Regra documentada mas não codificada (achado original)

Na revisão cruzada com o `data_dictionary.md`, encontramos que o `schema.yml` de `int_cancellations` **já descrevia** a regra "`refund_amount` não deve exceder o `total_amount` da reserva associada" — mas o SQL do modelo nunca implementava essa validação (o `total_amount` da reserva nem era trazido pra dentro da query). Ou seja: a regra estava documentada, só não estava codificada. Corrigimos trazendo `total_amount` de `stg_bookings` pra dentro do modelo e filtrando `refund_amount is null or refund_amount <= booking_total_amount`. Com a query completa, dá pra confirmar que esse filtro remove 794 cancelamentos (número que ficou pendente na primeira versão deste documento).

### 4.2 — Bug de sintaxe em `stg_partners.sql` (achado na varredura final)

Na varredura mais ampla que fizemos por último, encontramos uma vírgula sobrando no `stg_partners.sql`, logo depois do CTE `base`:

```sql
with base as (
    select * from {{ source('raw', 'raw_partners') }}
),                          -- <- vírgula que não devia estar aqui

    select
        partner_id,
        ...
```

Isso é sintaxe inválida — um `WITH` com vírgula esperava outro CTE nomeado em seguida, não um `SELECT` solto. Testamos isolado no DuckDB e confirma: `Parser Error: syntax error at or near "select"`. Na prática, isso quer dizer que o `dbt build` não rodava mais no estado em que o arquivo estava.

**Como validamos e corrigimos:** removemos a vírgula (o resto do SELECT não mudou nada — é só o CTE virando a query final, do jeito que já devia ser). Como o ambiente não tinha mais acesso ao `dev.duckdb` da sessão anterior (é um artefato local, não versionado) nem conseguia baixar o pacote `dbt_expectations` via `dbt deps` (proxy sem rota pro `hub.getdbt.com`), reconstruímos o pipeline inteiro manualmente em DuckDB — resolvendo `source()`/`ref()` na mão, na ordem staging → intermediate → marts — e rodamos de novo as 5 queries do Desafio 2 em cima do resultado. As 4 que já tinham CSV publicado (`top_parceiros_receita`, `ltv_cohort`, `deteccao_bot_buscas`, `taxa_cancelamento_outliers`) bateram **exatamente igual**, número por número, ao que já estava em `sql/results/`. Como esperado — o bug era só de sintaxe, não mudava a lógica de nenhuma coluna. Aproveitamos e exportamos também o CSV da Q1 (`funil_conversao`), que até então não tinha sido salvo.

Esse tipo de coisa é exatamente o que esse processo de auditoria (documentação × código, e agora também "será que isso builda de verdade") foi pensado pra pegar antes da entrega final.

## 5. Desafio 2 — decisões e validações por query

### Q1 — Funil sessão → busca → reserva, por país e device

Premissas confirmadas em 09/09/2026:
- Base de sessões: `int_sessions` (não-bot, deduplicada).
- Conversão pra "busca": sessão presente em `int_searches`.
- Conversão pra "reserva": sessão presente em `fct_bookings` **e** cujo `booking_id` não aparece em `int_cancellations` — reservas canceladas não contam como conversão real, mesmo já tendo passado por todas as regras de `raw_bookings`.
- País e device herdados da sessão de origem (únicos lugares do funil onde esses atributos existem).
- Janela de tempo: período completo disponível nos dados (01/10/2024–31/03/2025), sem recorte.
- `country`/`device` nulos ou em branco viram `'Não identificado'` em vez de serem descartados, pra não perder volume do funil.
- Colunas de saída traduzidas pra português (`pais`, `dispositivo`) pra consumo direto por quem não é técnico.

**Validação:** conferimos de forma independente, reconstruindo a mesma lógica (staging → intermediate → fato) direto em cima dos CSVs brutos, fora do pipeline dbt. Os números bateram exatamente pras 21 combinações de país × device. Taxa de conversão geral (sessão → reserva) girou entre ~8,9% e ~10,2% conforme o segmento, com o Brasil concentrando o maior volume absoluto de sessões (BR/desktop: 15.639, BR/mobile: 15.327), como esperado por ser o mercado principal da operação. Revalidado de novo depois do fix do bug em `stg_partners.sql` (seção 4.2) — resultado idêntico.

### Q2 — Top 10 parceiros por volume de reservas nos últimos 90 dias, excluindo cancelamentos

Premissas confirmadas em 09-10/09/2026:
- Janela "últimos 90 dias": `max(booked_at)` de `fct_bookings` como referência de "hoje", já que o dataset não tem uma data corrente real.
- Verificação em duas camadas antes de contar uma reserva: (1) `status in ('confirmed', 'completed')` em `fct_bookings` — segue o glossário do `data_dictionary.md`, que define que reserva só gera receita nesses status; (2) do que sobrou, remove qualquer `booking_id` presente em `int_cancellations` (mesmo critério da Q1, cobre status desatualizado).

**Achado durante a construção (mudou o desenho da query):** ao montar a soma de receita por parceiro, vimos que os 20 parceiros do dataset têm reservas nas 5 moedas presentes na base (BRL, USD, ARS, CLP, COP) — não é um padrão de "um parceiro, uma moeda". O dataset não tem nenhuma tabela de câmbio. Somar `total_amount` entre moedas diferentes sem conversão dá um número sem sentido financeiro (é como somar reais, dólares e pesos como se fossem a mesma unidade).

**Decisão adotada:** a receita não aparece como uma coluna só somada. A query abre o valor em uma coluna por moeda (`total_BRL`, `total_USD`, `total_ARS`, `total_CLP`, `total_COP`), sem conversão. O ranking de "top 10" passa a usar `quantidade_reservas` (volume, métrica comparável entre parceiros independente de moeda) como critério principal, com empate desempatado por `total_BRL` — BRL assumido como moeda do mercado principal, por ser o país de origem da Rentcars no case.

**Pedido de dado externo pra uma próxima iteração:** pra reportar receita real convertida (em vez de aberta por moeda), seria preciso incorporar uma tabela de taxas de câmbio históricas cobrindo o período 01/10/2024–31/03/2025 pra BRL/USD/ARS/CLP/COP. O Banco Central do Brasil disponibiliza isso de graça e publicamente: dataset **"Taxas de Câmbio — todos os boletins diários"** no Portal de Dados Abertos do BCB (`dadosabertos.bcb.gov.br`), com API OData filtrável por período e moeda, exportável em CSV — cobre as 5 moedas encontradas nessa base. Ver: https://dadosabertos.bcb.gov.br/dataset/taxas-de-cambio-todos-os-boletins-diarios/resource/0439af6a-d9be-4bf7-bf1a-60583e5f4c1c

Revalidado depois do fix do bug em `stg_partners.sql` (seção 4.2) — resultado idêntico ao já publicado.

### Q3 — LTV médio por cohort de primeiro acesso (mês/ano)

Premissas confirmadas em 10/09/2026:
- LTV = receita acumulada por usuário dentro do período disponível nos dados (aproximação de "valor gerado até aqui", não o ciclo de vida completo do cliente — o dataset cobre só 6 meses). Não é contagem de sessões nem tempo até reservar.
- Mesma regra de validade de receita da Q2 (duas camadas: `status in ('confirmed','completed')` + fora de `int_cancellations`), mas **sem** corte de 90 dias — soma o período inteiro disponível.
- Aberto por moeda pelo mesmo motivo da Q2 (sem tabela de câmbio disponível).
- Cohort = mês/ano de `first_seen_at` (primeira sessão) em `dim_users`.
- Métrica reportada é a média de LTV por usuário na cohort, com denominador = **todos** os usuários da cohort (inclusive os que nunca reservaram, contados como LTV = 0) — reflete o valor médio real gerado pela cohort inteira, não só pelos pagantes.

**Achado:** de 37.891 usuários em `dim_users`, **926 (2,4%) têm `first_seen_at` nulo** — aparecem em reservas (`fct_bookings`) mas nunca tiveram sessão válida registrada em `int_sessions` (nem mesmo antes de excluir os bots). Esses usuários ficam de fora da análise de cohort por não terem um mês/ano de primeiro acesso pra agrupar. Candidato a investigação: pode ser reserva feita fora do funil rastreado (canal offline/parceiro, por exemplo) ou lacuna de instrumentação de sessão.

**Resultado:** 6 coortes mensais (2024-10 a 2025-03), com volume de usuários decrescente nas coortes mais recentes — padrão esperado, já que coortes recentes tiveram menos tempo dentro da janela de dados pra acumular reservas. Revalidado depois do fix do bug em `stg_partners.sql` — resultado idêntico.

### Q4 — Detecção de sessões suspeitas de bot (>50 buscas em janela de 5 min)

Premissas confirmadas em 10/09/2026:
- Base: `stg_searches` + `stg_sessions` (staging, sem o filtro de `is_bot` que já existe em `int_searches`/`int_sessions`) — de propósito, pra poder comparar o achado por volume contra a flag `is_bot` já existente.
- Janela **fixa** de 5 minutos (não deslizante) — escolhida por simplicidade. Validamos que essa simplificação não muda o resultado nesse dataset (a 2ª sessão com mais buscas no total tem só 7, longe do limiar de 50 — não tem rajada real na borda de um bloco que a janela fixa deixaria escapar).

**Achado:** só **1 sessão** em todo o dataset passa de 50 buscas numa janela de 5 minutos (68 buscas concentradas), e essa sessão **não estava marcada como `is_bot = True`** — exatamente o caso que o `data_dictionary.md` avisa ("nem todo comportamento automatizado está necessariamente marcado nessa flag"). Ou seja: a flag `is_bot` do dataset tem 0 falsos negativos capturados por volume de busca nesse teste específico, com exceção dessa 1 sessão que passou despercebida. Revalidado depois do fix do bug — resultado idêntico.

### Q5 — Taxa de cancelamento por parceiro, com outliers estatísticos (>2σ)

Premissas confirmadas em 10/09/2026:
- Taxa de cancelamento do parceiro = cancelamentos (via `int_cancellations`) / reservas do parceiro com `status in ('confirmed', 'completed')` — segue o glossário do `data_dictionary.md`, incluindo `completed` no denominador.
- Outlier aplicado sobre a distribuição das taxas entre os parceiros (não sobre contagem bruta): média e desvio-padrão das taxas de todos os parceiros, outlier = taxa > média + 2σ.
- Sem corte de janela temporal.

**Explicação do método (2σ), pra referência técnica futura:** assumindo que as taxas de cancelamento dos parceiros seguem aproximadamente uma distribuição normal, cerca de 95% dos valores caem dentro de 2 desvios-padrão da média — é a regra empírica de distribuições normais (68-95-99.7). Um parceiro cuja taxa passa de `média + 2σ` está fora do padrão estatisticamente esperado do grupo: não é prova de problema, mas é um sinal forte o bastante pra não ser só variação aleatória, e que justifica investigação.

**Resultado:** média geral de 34,41% de cancelamento, desvio-padrão de 2,44 pontos percentuais, limite de outlier em 39,28%. **Nenhum parceiro passou do limite** — o mais próximo foi a TopDrive, com 38,16% (a menos de 1,2 ponto percentual do limite), que vale monitorar mesmo não sendo formalmente um outlier nessa análise. Revalidado depois do fix do bug — resultado idêntico.

## 6. Limitações e itens em aberto

- "Múltiplas reservas do mesmo usuário no mesmo dia" (16 usuários / 34 reservas) e "`days_before_pickup` negativo" (93 cancelamentos) são sinalizados pelo dicionário como possíveis indícios de fraude/anomalia, e agora já temos os números exatos — mas ainda não viraram teste ou flag em nenhum modelo. Ficam como candidatos a uma investigação ad-hoc ou a testes futuros.
- Outliers de `total_amount` por categoria (~101 casos, IQR) e a categoria `compact` fora do domínio canônico do dicionário também não têm teste associado ainda — acabaram de ser quantificados nessa última varredura, mas tratar isso em modelo (filtro, flag, ou teste `accepted_values`/`dbt_expectations`) fica pra uma próxima iteração.
- Sessões com duração acima de 6h (589 casos, até 72h) e buscas com `partner_id_clicked` preenchido apesar de `num_results = 0` (1.197 casos) são achados novos dessa varredura final, sem tratamento em modelo — mais candidatos a investigação, não bloqueiam nada hoje.
- `dim_users` cobre só usuários autenticados (com `user_id`); sessões e reservas 100% anônimas não geram linha de dimensão, ficando nos fatos com `user_id` nulo.
- Ambiente local: `dbt deps` (pacote `dbt_expectations`) e o `dev.duckdb` da sessão anterior não estavam disponíveis nessa etapa final por causa do ambiente de execução (ver seção 4.2) — o pipeline foi revalidado manualmente em DuckDB puro, resolvendo `ref()`/`source()` na mão, e os resultados bateram com o que já estava publicado. Recomenda-se rodar `dbt build` de verdade (com rede liberada pro `hub.getdbt.com`) antes da entrega final, pra garantir que os testes `dbt_expectations` citados ao longo deste documento também passam via dbt nativo, não só pela revalidação manual.
