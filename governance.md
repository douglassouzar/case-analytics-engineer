# Governança de Dados, Case Rentcars

## 1. Contexto e metodologia

Os 5 datasets brutos, `raw_partners`, `raw_sessions`, `raw_searches`, `raw_bookings`, `raw_cancellations`, vêm com problemas de qualidade **de propósito**, como o próprio `data_dictionary.md` do case avisa. Este documento junta o que encontrei na verificação, as regras de negócio descritas no dicionário, e o que fiz, ou decidi não fazer e por quê, com cada uma delas ao longo das camadas staging, intermediate e marts.

Como cheguei até aqui: primeiro uma verificação de nulos e duplicatas tabela por tabela, depois uma comparação linha a linha entre as "Regras de negócio" do `data_dictionary.md` e o que estava de fato implementado em cada modelo dbt. Essa auditoria pegou uma divergência real entre documentação e código, seção 4. Por fim, já perto da entrega, fiz uma segunda verificação mais ampla e sistemática, cobrindo domínios categóricos, formatos inconsistentes, outliers e regras de negócio que ainda não tinham sido checadas com números, que também achou coisa nova, incorporada ao longo das seções abaixo.

Os testes automatizados, `dbt test`, rodam em dois níveis de severidade: **error**, pras regras que precisam sempre valer no dado final, por exemplo unicidade em intermediate e marts, e **warn**, pros achados de qualidade conhecidos e propositais, que eu meço mas não deixo travar o pipeline, por exemplo duplicatas em staging, antes da deduplicação.

## 2. Duplicatas encontradas, staging, antes da deduplicação

| Tabela | Linhas totais | Chaves com duplicata | % |
|---|---|---|---|
| `raw_partners` | 22 | 2 | ~9% |
| `raw_sessions` | 120.350 | 342 | ~0,3% |
| `raw_searches` | 80.240 | 236 | ~0,3% |
| `raw_bookings` | 18.124 | 118 | ~0,7% |
| `raw_cancellations` | 4.410 | 79 | ~1,8% |

Conferi linha a linha: em todos os casos as duplicatas são cópias exatas da mesma linha, mesmo `booking_id`/`session_id`/etc. com todos os outros campos idênticos, não são versões conflitantes do mesmo registro. Isso simplifica a deduplicação: não tem "qual versão é a certa", é só remover a cópia.

**Tratamento:** todas deduplicadas na camada `intermediate`, mantendo o registro mais recente por chave. Critério de recência: `updated_at`/`created_at` pra partners, `started_at` pra sessions, `searched_at` pra searches, `booked_at` pra bookings, `cancelled_at` pra cancellations. Os testes `unique` em `staging/schema.yml` ficam com `severity: warn` de propósito, já que é esperado que staging, camada 1:1 com a fonte e sem lógica de negócio, carregue essas duplicatas. A garantia real de unicidade só é cobrada como `error` a partir de `intermediate` em diante.

## 3. Regras de negócio do `data_dictionary.md` × implementação

### raw_partners → int_partners → dim_partners
| Regra | Onde é aplicada | Status |
|---|---|---|
| Somente `status = active` recebe reservas | Filtro, inner join, em `int_bookings` | ✅ Aplicada |
| `commission_rate` entre 0.05 e 0.30 | Teste `dbt_expectations` em `dim_partners` | ✅ Testada, 0 violações nos 22 parceiros |
| `partner_id` único | Deduplicação em `int_partners` + teste `unique`, severity error | ✅ Aplicada e testada |

**Achados extras, não são regras do dicionário, mas apareceram na verificação:**
- `status` chega com 3 formatos diferentes, `active`, `Active`, `inactive`. O `stg_partners` já normaliza com `lower(trim())`, então o filtro de `status = active` funciona certo mesmo assim. Só registrando porque, sem essa normalização, os 2 parceiros gravados como `Active`, maiúsculo, cairiam fora do filtro por engano.
- `country`: o dicionário descreve 3% de nulo esperado nessa coluna, mas os dados reais não têm nenhum nulo, 0%. É só uma divergência entre o que o dicionário descreve e o dado real, não afeta nada no pipeline, mas vale registrar.

### raw_sessions → int_sessions → fct_sessions
| Regra | Onde é aplicada | Status |
|---|---|---|
| `is_bot = true` excluído das análises | Filtro em `int_sessions` | ✅ Aplicada |
| `ended_at` posterior a `started_at` | Teste `dbt_expectations`, severity warn, em `int_sessions` | ✅ Testada, **0 violações**, a regra vale sempre nos dados |
| "Nem todo bot está marcado na flag" | Detecção heurística, mais de 50 buscas em 5 minutos | Tratada no Desafio 2, Q4, não em modelo dbt |

**Achados extras:**
- `device` e `country` chegam com formatação inconsistente, `DESKTOP`/`desktop`, `Mobile`/`mobile`, `BR`/`br`/`Br`. De novo, já normalizado em staging, `lower(trim())` pra device, `upper(trim())` pra country, então o funil da Q1 não fica distorcido. Sem essa normalização, o Brasil apareceria fatiado em 3 países diferentes no resultado.
- **589 sessões com duração acima de 6 horas** no raw, 571 já em cima de `int_sessions`, pós-deduplicação e exclusão de bot, a mais longa chegando a quase 72h. O dicionário diz que "sessões são encerradas após 30 min de inatividade" e que a duração típica não passa de algumas horas, então essas sessões longas contrariam essa expectativa na prática. Agora monitorada via teste singular `teste_duracao_sessao`, severity warn, limiar de 6h, ver justificativa do limiar na seção 8, SLA de dados. Fica como candidato a investigação, pode ser bug no cálculo de `ended_at`, sessão que nunca fechou, ou outro padrão de bot que passou batido pela flag `is_bot`.

### raw_searches → int_searches, consumida em Q1/Q4 do D2
| Regra | Onde é aplicada | Status |
|---|---|---|
| `search_id` único | Deduplicação em `int_searches` + teste `unique`, severity error | ✅ Aplicada e testada |
| Buscas de sessão `is_bot=true` descartadas | Join com `int_sessions`, não mais `stg_sessions` | ✅ Corrigida, gap encontrado e corrigido: a versão inicial usava `stg_sessions`, que não filtra bot |
| `partner_id_clicked` deve existir em `raw_partners` | Teste `relationships`, severity warn, contra `int_partners` | ✅ Testada, **0 violações** |
| `dropoff_date >= pickup_date` | Teste `dbt_expectations`, severity warn, em `int_searches` | ⚠️ Testada, **739 violações**, ~0,9% de 80.240 buscas têm `dropoff_date` antes de `pickup_date`, já contando com deduplicação. Mantidas na tabela, só sinalizadas via teste. Decisão: não descartar, porque é um campo de intenção de busca, não uma transação financeira |

**Achados extras:**
- `car_category`: além das 5 categorias do domínio canônico do dicionário, `economy, suv, luxury, pickup, minivan`, aparece uma 6ª, `compact`, tanto em `raw_searches`, 11.566 linhas, quanto em `raw_bookings`, 2.556 linhas. Não é erro de formatação, já vem em minúsculo, sem espaço extra, é uma categoria a mais que o dicionário não previa. Staging normaliza texto mas não validava contra a lista esperada. Agora valida: teste `accepted_values`, severity warn, em `stg_searches.car_category` e `stg_bookings.car_category` contra o domínio original de 5 categorias, então `compact` aparece como warning a cada `dbt test` em vez de passar despercebido.
- **1.197 buscas no raw** têm `partner_id_clicked` preenchido mas `num_results = 0`, ou seja, o usuário "clicou" num parceiro num resultado que, segundo o dado, não deveria ter aparecido. É uma inconsistência lógica entre duas colunas da mesma linha, não coberta por nenhuma regra do dicionário. Monitorada via teste singular `teste_clique_sem_resultado`, severity warn. O `dbt test` real em `int_searches` deu **1.163**, a verificação manual antes tinha dado 1.195, pequena divergência ainda sob investigação, ver seção 6.3. Fica como achado pra investigação futura, pode ser problema de instrumentação do evento de clique.

### raw_bookings → int_bookings → fct_bookings
| Regra | Onde é aplicada | Status |
|---|---|---|
| `booking_id` único | Deduplicação em `int_bookings` + teste `unique`, severity error | ✅ Aplicada e testada |
| `total_amount > 0` para `confirmed`/`completed` | Filtro em `int_bookings` | ✅ Aplicada, **156 reservas** removidas por esse filtro, incluindo valores negativos, o menor sendo -R$484,89, e reservas com `total_amount = 0`. Mais **297 reservas** `confirmed`/`completed` com `total_amount` nulo também ficam fora |
| Valores de `total_amount` muito acima do padrão da categoria devem ser investigados | não aplicável | ⚠️ Não tratada em modelo, ver achado abaixo |
| `dropoff_date` posterior a `pickup_date` | Teste `dbt_expectations`, severity warn, em `int_bookings` | ✅ Testada, **0 violações** |
| `partner_id` existe e ativo em `raw_partners` | Filtro, inner join com parceiros ativos, em `int_bookings` | ✅ Aplicada, reservas de parceiro inativo ou inexistente são excluídas do fato, não só flagadas, decisão de modelagem |
| Deduplicar antes de agregação financeira | Deduplicação em `int_bookings` | ✅ Aplicada |
| Múltiplas reservas mesmo usuário/dia = possível fraude | Teste singular `teste_reservas_duplicadas_usuario_dia`, severity warn, em `int_bookings` | ⚠️ Monitorada, não filtrada, **16 usuários com 34 reservas** no raw, 34 reservas envolvidas, um caso chega a 4 no mesmo dia. Medido de novo já em cima de `int_bookings`, pós-filtro de parceiro ativo e total_amount, o teste aponta **10 combinações usuário+dia** com mais de 1 reserva. Decisão: não bloquear no fato, é candidata a fraude, não uma certeza, e merece revisão humana antes de qualquer exclusão automática |

**Achado quantificado, outliers de `total_amount` por categoria:** rodei IQR, 1.5×, sobre `total_amount` de reservas `confirmed`/`completed`, deduplicadas, separando por `car_category`. No raw deduplicado deu ~101 outliers espalhados pelas 7 categorias, incluindo `compact` e nulo. Já em cima de `int_bookings`, pós-filtro de parceiro ativo, esse número cai pra **91**. Os casos mais chamativos: `pickup`, 22 outliers no raw, limite superior ~R$7.901, máximo encontrado R$79.311, 10x o limite, e `economy`, 9 outliers, limite ~R$7.953, máximo R$77.361. Isso responde diretamente à regra do dicionário sobre "valores muito acima do padrão da categoria", que até então não tinha nenhuma checagem associada. Agora tem: teste singular `teste_outlier_valor_por_categoria`, severity warn, em `int_bookings`, mesmo método, IQR por categoria, rodando a cada `dbt test`.

**Também vale registrar:** `total_amount` negativo aparece em **178 reservas no total**, não só nas `confirmed`/`completed`, ou seja, o problema não é exclusivo do filtro de receita, é um padrão mais amplo no dado bruto.

### raw_cancellations → int_cancellations
| Regra | Onde é aplicada | Status |
|---|---|---|
| `cancellation_id` único | Deduplicação em `int_cancellations` + teste `unique`, severity error | ✅ Aplicada e testada |
| `booking_id` existe em `raw_bookings` | Filtro, inner join, em `int_cancellations` | ✅ Aplicada |
| Reserva tem no máximo 1 cancelamento associado | Consequência natural da deduplicação por `booking_id` | ✅ Conferida, depois da deduplicação, **0 reservas** têm mais de um cancelamento. As 80 ocorrências que apareceram numa primeira olhada eram só efeito das linhas duplicadas do raw, não cancelamentos reais em duplicidade |
| `refund_amount` não excede `total_amount` da reserva | Filtro em `int_cancellations` + teste singular `teste_reembolso_maior_que_total`, severity warn, em staging | ✅ Aplicada e monitorada, **794 cancelamentos** removidos por esse filtro, contagem que antes estava pendente, ver seção 4. O teste roda sobre a camada staging, antes do filtro, pra deixar esse volume visível a cada `dbt test`, em vez de só desaparecer silenciosamente |
| `days_before_pickup` negativo = cancelamento tardio | Teste `dbt_expectations.expect_column_values_to_be_between`, severity warn, em `stg_cancellations` | ⚠️ Monitorada, não filtrada, **93 cancelamentos** com `days_before_pickup` negativo, o pior caso é -2 dias. Decisão: não excluir, é um caso raro mas legítimo, cancelamento após início da locação, só precisa ficar visível |

## 4. Achado de auditoria: regra documentada mas não codificada

Na revisão cruzada com o `data_dictionary.md`, encontrei que o `schema.yml` de `int_cancellations` **já descrevia** a regra "`refund_amount` não deve exceder o `total_amount` da reserva associada", mas o SQL do modelo nunca implementava essa validação, o `total_amount` da reserva nem era trazido pra dentro da query. Ou seja, a regra estava documentada, só não estava codificada. Corrigi trazendo `total_amount` de `stg_bookings` pra dentro do modelo e filtrando `refund_amount is null or refund_amount <= booking_total_amount`. Com a query completa, dá pra confirmar que esse filtro remove 794 cancelamentos, número que ficou pendente na primeira versão deste documento.

Esse tipo de coisa é exatamente o que esse processo de auditoria, documentação × código, foi pensado pra pegar antes da entrega final.

## 5. Desafio 2, decisões e validações por query

### Q1, funil sessão → busca → reserva, por país e device

Premissas confirmadas em 09/09/2026:
- Base de sessões: `int_sessions`, não-bot, deduplicada.
- Conversão pra "busca": sessão presente em `int_searches`.
- Conversão pra "reserva": sessão presente em `fct_bookings` **e** cujo `booking_id` não aparece em `int_cancellations`, reservas canceladas não contam como conversão real, mesmo já tendo passado por todas as regras de `raw_bookings`.
- País e device herdados da sessão de origem, únicos lugares do funil onde esses atributos existem.
- Janela de tempo: período completo disponível nos dados, 01/10/2024 a 31/03/2025, sem recorte.
- `country`/`device` nulos ou em branco viram `'Não identificado'` em vez de serem descartados, pra não perder volume do funil.
- Colunas de saída traduzidas pra português, `pais`, `dispositivo`, pra consumo direto por quem não é técnico.

**Validação:** conferi de forma independente, reconstruindo a mesma lógica, staging, intermediate, fato, direto em cima dos CSVs brutos, fora do pipeline dbt. Os números bateram exatamente pras 21 combinações de país × device. Taxa de conversão geral, sessão → reserva, girou entre ~8,9% e ~10,2% conforme o segmento, com o Brasil concentrando o maior volume absoluto de sessões, BR/desktop: 15.639, BR/mobile: 15.327, como esperado por ser o mercado principal da operação.

### Q2, top 10 parceiros por volume de reservas nos últimos 90 dias, excluindo cancelamentos

Premissas confirmadas em 09-10/09/2026:
- Janela "últimos 90 dias": `max(booked_at)` de `fct_bookings` como referência de "hoje", já que o dataset não tem uma data corrente real.
- Verificação em duas camadas antes de contar uma reserva: primeiro, `status in ('confirmed', 'completed')` em `fct_bookings`, segue o glossário do `data_dictionary.md`, que define que reserva só gera receita nesses status; segundo, do que sobrou, remove qualquer `booking_id` presente em `int_cancellations`, mesmo critério da Q1, cobre status desatualizado.

**Achado durante a construção, mudou o desenho da query:** ao montar a soma de receita por parceiro, vi que os 20 parceiros do dataset têm reservas nas 5 moedas presentes na base, BRL, USD, ARS, CLP, COP, não é um padrão de "um parceiro, uma moeda". O dataset não tem nenhuma tabela de câmbio. Somar `total_amount` entre moedas diferentes sem conversão dá um número sem sentido financeiro, é como somar reais, dólares e pesos como se fossem a mesma unidade.

**Decisão adotada:** a receita não aparece como uma coluna só somada. A query abre o valor em uma coluna por moeda, `total_BRL`, `total_USD`, `total_ARS`, `total_CLP`, `total_COP`, sem conversão. O ranking de "top 10" passa a usar `quantidade_reservas`, volume, métrica comparável entre parceiros independente de moeda, como critério principal, com empate desempatado por `total_BRL`, BRL assumido como moeda do mercado principal, por ser o país de origem da Rentcars no case.

**Pedido de dado externo pra uma próxima iteração:** pra reportar receita real convertida, em vez de aberta por moeda, seria preciso incorporar uma tabela de taxas de câmbio históricas cobrindo o período 01/10/2024 a 31/03/2025 pra BRL/USD/ARS/CLP/COP. O Banco Central do Brasil disponibiliza isso de graça e publicamente, dataset "Taxas de Câmbio, todos os boletins diários", no Portal de Dados Abertos do BCB, `dadosabertos.bcb.gov.br`, com API OData filtrável por período e moeda, exportável em CSV, cobre as 5 moedas encontradas nessa base. Ver: https://dadosabertos.bcb.gov.br/dataset/taxas-de-cambio-todos-os-boletins-diarios/resource/0439af6a-d9be-4bf7-bf1a-60583e5f4c1c

### Q3, LTV médio por cohort de primeiro acesso, mês/ano

Premissas confirmadas em 10/09/2026:
- LTV = receita acumulada por usuário dentro do período disponível nos dados, aproximação de "valor gerado até aqui", não o ciclo de vida completo do cliente, já que o dataset cobre só 6 meses. Não é contagem de sessões nem tempo até reservar.
- Mesma regra de validade de receita da Q2, duas camadas, `status in ('confirmed','completed')` mais fora de `int_cancellations`, mas **sem** corte de 90 dias, soma o período inteiro disponível.
- Aberto por moeda pelo mesmo motivo da Q2, sem tabela de câmbio disponível.
- Cohort = mês/ano de `first_seen_at`, primeira sessão, em `dim_users`.
- Métrica reportada é a média de LTV por usuário na cohort, com denominador = **todos** os usuários da cohort, inclusive os que nunca reservaram, contados como LTV = 0, reflete o valor médio real gerado pela cohort inteira, não só pelos pagantes.

**Achado:** de 37.891 usuários em `dim_users`, **926, 2,4%, têm `first_seen_at` nulo**, aparecem em reservas, `fct_bookings`, mas nunca tiveram sessão válida registrada em `int_sessions`, nem mesmo antes de excluir os bots. Esses usuários ficam de fora da análise de cohort por não terem um mês/ano de primeiro acesso pra agrupar. Candidato a investigação: pode ser reserva feita fora do funil rastreado, canal offline ou parceiro, por exemplo, ou lacuna de instrumentação de sessão.

**Resultado:** 6 coortes mensais, 2024-10 a 2025-03, com volume de usuários decrescente nas coortes mais recentes, padrão esperado, já que coortes recentes tiveram menos tempo dentro da janela de dados pra acumular reservas.

### Q4, detecção de sessões suspeitas de bot, mais de 50 buscas em janela de 5 min

Premissas confirmadas em 10/09/2026:
- Base: `stg_searches` + `stg_sessions`, staging, sem o filtro de `is_bot` que já existe em `int_searches`/`int_sessions`, de propósito, pra poder comparar o achado por volume contra a flag `is_bot` já existente.
- Janela **fixa** de 5 minutos, não deslizante, escolhida por simplicidade. Validei que essa simplificação não muda o resultado nesse dataset, a 2ª sessão com mais buscas no total tem só 7, longe do limiar de 50, não tem rajada real na borda de um bloco que a janela fixa deixaria escapar.

**Achado:** só **1 sessão** em todo o dataset passa de 50 buscas numa janela de 5 minutos, 68 buscas concentradas, e essa sessão **não estava marcada como `is_bot = True`**, exatamente o caso que o `data_dictionary.md` avisa, "nem todo comportamento automatizado está necessariamente marcado nessa flag". Ou seja, a flag `is_bot` do dataset tem 0 falsos negativos capturados por volume de busca nesse teste específico, com exceção dessa 1 sessão que passou despercebida.

### Q5, taxa de cancelamento por parceiro, com outliers estatísticos, mais de 2σ

Premissas confirmadas em 10/09/2026:
- Taxa de cancelamento do parceiro = cancelamentos, via `int_cancellations`, dividido por reservas do parceiro com `status in ('confirmed', 'completed')`, segue o glossário do `data_dictionary.md`, incluindo `completed` no denominador.
- Outlier aplicado sobre a distribuição das taxas entre os parceiros, não sobre contagem bruta: média e desvio-padrão das taxas de todos os parceiros, outlier = taxa maior que média + 2σ.
- Sem corte de janela temporal.

**Explicação do método, 2σ, pra referência técnica futura:** assumindo que as taxas de cancelamento dos parceiros seguem aproximadamente uma distribuição normal, cerca de 95% dos valores caem dentro de 2 desvios-padrão da média, é a regra empírica de distribuições normais, 68-95-99.7. Um parceiro cuja taxa passa de `média + 2σ` está fora do padrão estatisticamente esperado do grupo: não é prova de problema, mas é um sinal forte o bastante pra não ser só variação aleatória, e que justifica investigação.

**Resultado:** média geral de 34,41% de cancelamento, desvio-padrão de 2,44 pontos percentuais, limite de outlier em 39,28%. **Nenhum parceiro passou do limite**, o mais próximo foi a TopDrive, com 38,16%, a menos de 1,2 ponto percentual do limite, que vale monitorar mesmo não sendo formalmente um outlier nessa análise.

## 6. Evidências das validações implementadas

Essa seção foi atualizada com o log real de `dbt test`, rodado no ambiente local, Windows/PowerShell, 09/09/2026, 44 testes no total. Antes disso, os números tinham sido só verificados manualmente em DuckDB, por uma limitação de rede do ambiente usado naquele momento. A rodada real confirmou a maioria, corrigiu um bug real que só apareceria rodando de verdade, e deixou uma pequena divergência ainda sob investigação, ver 6.3.

### 6.1 Bug real encontrado só na rodada de `dbt test`

Os 5 testes `unique` de `staging/schema.yml`, `stg_partners`, `stg_sessions`, `stg_searches`, `stg_bookings`, `stg_cancellations`, rodaram como **error** e falharam, 118, 79, 2, 236, 342 duplicatas, exatamente as contagens da tabela da seção 2, mesmo esse documento dizendo desde a primeira versão que staging deveria ser `severity: warn`. O `schema.yml` tinha o teste declarado, `tests: [not_null, unique]`, mas nunca tinha o `config: severity: warn` de fato aplicado, documentação e código divergindo de novo, mesmo padrão do achado da seção 4, só que dessa vez só a rodada real do `dbt test` pegou, a verificação manual em DuckDB não simula severidade de teste, só a query em si. **Corrigido:** `unique` virou uma entrada própria com `config: severity: warn` em cada uma das 5 colunas. Também aproveitei pra corrigir um aviso de depreciação que apareceu no log, `MissingArgumentsPropertyInGenericTestDeprecation`, argumentos de teste genérico precisam ficar aninhados em `arguments:`, não soltos. Não travava nada, mas ia virar erro em versão futura do dbt.

### 6.2 Testes genéricos e `dbt_expectations` novos, `schema.yml`, severity warn, confirmados via `dbt test` real

| Teste | Modelo/coluna | Violações, dbt test real |
|---|---|---|
| `accepted_values`, domínio original de 5 categorias | `stg_bookings.car_category` | 2.556 |
| `accepted_values`, domínio original de 5 categorias | `stg_searches.car_category` | 11.566 |
| `dbt_expectations.expect_column_values_to_be_between`, `days_before_pickup >= 0` | `stg_cancellations.days_before_pickup` | 93 |

Todos batem exatamente com o que tinha sido verificado manualmente.

### 6.3 Testes singulares novos, `tests/*.sql`, severity warn, confirmados via `dbt test` real

| Arquivo | O que verifica | Verificado manualmente, DuckDB | `dbt test` real |
|---|---|---|---|
| `teste_reservas_duplicadas_usuario_dia.sql` | Mesmo usuário com mais de 1 reserva no mesmo dia | 10 | **10** ✅ |
| `teste_duracao_sessao.sql` | Sessão com duração maior que 6h | 571 | **571** ✅ |
| `teste_outlier_valor_por_categoria.sql` | Outlier de `total_amount` por `car_category`, IQR 1.5× | 91 | **91** ✅ |
| `teste_reembolso_maior_que_total.sql` | `refund_amount > total_amount` da reserva | 794 | **794** ✅ |
| `teste_clique_sem_resultado.sql` | `partner_id_clicked` preenchido com `num_results = 0` | 1.195 | **1.163** ⚠️, 32 a menos |

4 dos 5 bateram exatamente. O `teste_clique_sem_resultado` divergiu em 32 casos, 1.163 no ambiente real contra 1.195 na verificação manual. A lógica do teste está correta, mesma query rodando nos dois lugares, a suspeita é diferença de carregamento do CSV bruto entre o `external_location` do dbt-duckdb e o `read_csv_auto` usado na verificação manual. Não muda a existência do achado, ainda é o teste mais volumoso depois do `refund_amount`, só o número exato está sendo investigado, e o `dbt test` real, 1.163, é o número que vale como oficial até resolver.

Todos os testes novos usam `severity: warn` de propósito, são achados de qualidade conhecidos e propositais do case, não bugs a corrigir às pressas. A ideia é que fiquem visíveis e quantificados a cada rodada de `dbt test`, sem travar o pipeline. Se algum desses volumes crescer muito de uma rodada pra outra, é sinal de um problema novo, não só o "ruído" original do dataset, ver os thresholds da seção 8.

**Resultado da rodada real, antes do fix da seção 6.1:** `Done. PASS=30 WARN=9 ERROR=5 SKIP=0 TOTAL=44`, os 5 erros eram só os `unique` de staging sem `severity: warn`.

**Resultado depois do fix, confirmado com novo `dbt test` em 09/09/2026:** `Done. PASS=30 WARN=14 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=44`, os 5 erros viraram warning, unicidade em staging é esperada, tratada a partir de `intermediate`, somando aos 9 warnings que já existiam, total 14. **Pipeline passa limpo, sem nenhum error.** Essa é a evidência oficial do item 6 do D4.

## 7. Catálogo de dados, marts e glossário de métricas

### 7.1 Modelos e colunas

A documentação completa de cada coluna dos 4 marts, `dim_partners`, `dim_users`, `fct_bookings`, `fct_sessions`, está em `models/marts/schema.yml`, inclui grão, descrição de cada campo, e a flag `meta.contains_pii`, ver seção 9. Resumo do grão de cada um:

| Mart | Grão | O que representa |
|---|---|---|
| `dim_partners` | 1 linha por `partner_id` | Cadastro das locadoras parceiras, nome, país, tier, comissão, status |
| `dim_users` | 1 linha por `user_id` | Usuários autenticados, anônimos não entram aqui |
| `fct_bookings` | 1 linha por `booking_id` | Reservas, incremental, já validadas, parceiro ativo, `total_amount > 0` para confirmed/completed, deduplicado |
| `fct_sessions` | 1 linha por `session_id` | Sessões de navegação, incremental, sem bot, deduplicado |

### 7.2 Glossário de métricas

Definições oficiais do `data_dictionary.md`, com a fórmula exata usada nos modelos e queries deste projeto, não só a definição textual do case:

| Métrica | Definição | Como é calculada aqui |
|---|---|---|
| **Taxa de Conversão** | Proporção de sessões que resultam em ao menos uma reserva confirmada | `fct_bookings`, status confirmed/completed, fora de `int_cancellations`, dividido por `int_sessions`, por país×device, ver Q1, seção 5 |
| **Ticket Médio** | Valor médio de `total_amount` para reservas confirmadas ou concluídas | `avg(total_amount)` em `fct_bookings` filtrado por `status in ('confirmed','completed')`, sempre aberto por `currency`, sem tabela de câmbio, ver Q2 |
| **Taxa de Cancelamento** | % de reservas canceladas sobre o total de reservas confirmadas | `int_cancellations`, via `booking_id`, dividido por `fct_bookings` com `status in ('confirmed','completed')`, por parceiro, ver Q5 |
| **LTV, Lifetime Value** | Valor gerado por usuário dentro do período disponível, aqui é uma aproximação, 6 meses de dados, não o ciclo de vida completo | Soma de `total_amount` válido, confirmed/completed, não cancelado, por `user_id`, com denominador = todos os usuários da cohort, LTV=0 pra quem nunca reservou, ver Q3 |
| **Tier** | Nível de parceria comercial: gold > silver > bronze | Campo direto de `dim_partners.tier`, 13,6% nulo, não classificado |
| **Canal de Aquisição** | Origem da sessão | Campo direto de `fct_sessions.channel`, normalizado em staging |
| **Daily Rate** | Valor cobrado por diária de locação, moeda local | Campo direto de `fct_bookings.daily_rate` |

## 8. SLA de dados, quando um dado é "confiável"?

Não existe um SLA formal definido no `data_dictionary.md` do case, ele não dá números de threshold, então os limiares abaixo foram definidos por mim, a partir do que a verificação mostrou como "normal" nesse dataset, documentando o raciocínio, não só o número.

### 8.1 Frescor, freshness

- `fct_bookings` e `fct_sessions` são incrementais, `delete+insert`, filtrando por `booked_at`/`started_at` mais recente que o já carregado. Num cenário produtivo, o SLA proposto é: **dado é considerado "atual" se o `dbt run` incremental rodou nas últimas 24h**. Rodadas incrementais paradas por mais de 24h devem disparar alerta, não tenho orquestração, Airflow/Cron, configurada neste case, mas é o gancho natural pra isso.

### 8.2 Completude, completeness

- Colunas-chave, `booking_id`, `session_id`, `partner_id`, `search_id`, `cancellation_id`, **0% de nulo tolerado**. Já garantido por `not_null`, severity error, em todas as camadas a partir de `intermediate`.
- `total_amount` em reservas `confirmed`/`completed`, **0% de nulo tolerado** pra entrar em métrica de receita. Hoje 297 reservas violam isso e são filtradas em `int_bookings`, não entram no fato. Threshold: se esse volume passar de ~2% do total de reservas confirmed/completed numa rodada, é sinal de problema novo na fonte, não mais o "ruído" conhecido do case.
- Campos com nulo declarado como esperado no dicionário, `tier` 14%, `utm_source` 29%, `payment_method` 25%, etc., **tolerância = a % declarada no `data_dictionary.md` ± 3 pontos percentuais**. Fora dessa faixa, é sinal de mudança de comportamento na origem do dado, por exemplo um novo sistema deixou de preencher um campo que antes preenchia.

### 8.3 Unicidade, uniqueness

- Chaves primárias de `intermediate` em diante: **100% únicas, sem exceção**, garantido por teste `unique`, severity error. Duplicatas só são toleradas em `staging`, severity warn, porque ali é esperado, 1:1 com a fonte, sem lógica de negócio.

### 8.4 Validade, validity, domínio e regras de negócio

- Testes `severity: error`, não podem falhar nunca numa rodada saudável: unicidade e not-null de chave primária a partir de `intermediate`, `commission_rate` no range contratual.
- Testes `severity: warn`, achados propositais do case, mas com um teto de tolerância pra não virar "ruído aceito pra sempre": a tabela abaixo define o threshold que, se ultrapassado, deveria virar investigação obrigatória, não só um número monitorado.

| Achado, warn | Volume medido hoje | Threshold proposto pra virar alerta |
|---|---|---|
| Categoria fora do domínio, `compact` | 2.556 bookings / 11.566 searches | Se aparecer uma categoria **nova além dessas 6**, uma 7ª, alerta imediato, hoje é um domínio estável, mesmo que maior que o esperado |
| `days_before_pickup` negativo | 93 | Alerta se ultrapassar 3% dos cancelamentos, hoje é ~2,1% |
| Múltiplas reservas mesmo usuário/dia | 10 combinações, em `int_bookings` | Alerta se ultrapassar 0,5% dos usuários com reserva no período, hoje está bem abaixo disso |
| Outlier de `total_amount` por categoria | 91, em `int_bookings` | Alerta se ultrapassar 1% das reservas confirmed/completed por categoria, hoje está em ~0,6% |
| Sessão maior que 6h de duração | 571, em `int_sessions` | Alerta se ultrapassar 1% do total de sessões, hoje está em ~0,5% |
| Clique sem resultado, `num_results=0` | 1.163, `dbt test` real em `int_searches` | Alerta se ultrapassar 2% das buscas, hoje está em ~1,5% |
| `refund_amount > total_amount` | 794 | Alerta se ultrapassar 20% dos cancelamentos, hoje está em ~18%, já é o achado mais volumoso do dataset, vale acompanhar de perto mesmo dentro do threshold |

### 8.5 Definição prática de "dado confiável"

Juntando tudo: **um mart é considerado confiável pra uso em decisão de negócio quando a última rodada incremental tem menos de 24h, todos os testes `severity: error` passaram, e nenhum teste `severity: warn` ultrapassou o threshold da tabela 8.4.** Esse é o critério que proponho pra virar um gate de CI, por exemplo Buildkite ou GitHub Actions rodando `dbt build` a cada PR e bloqueando merge se `error` falhar. Não implementado neste case por restrição de tempo, mas é a recomendação natural de próximo passo.

## 9. Política de PII

### 9.1 O que existe de PII neste dataset

Perfil bom pra esse tipo de análise: o dataset **não tem nome de pessoa física, CPF, telefone ou endereço em nenhuma das 5 tabelas**. Os campos sensíveis são mais restritos do que num dataset típico de CRM:

| Campo | Tabela(s) | Classificação | Por quê |
|---|---|---|---|
| `user_id` | `raw_sessions`, `raw_bookings`, `dim_users`, `fct_bookings`, `fct_sessions` | **Identificador indireto** | É um UUID, não carrega nome, e-mail ou documento diretamente, mas permite religar todo o histórico de navegação e reserva de uma pessoa se cruzado com outra fonte, por exemplo sistema de autenticação |
| `contact_email` | `raw_partners`, `dim_partners` | **Dado de contato, Restrito** | E-mail operacional de empresa parceira, por exemplo `ops@localiza.com`, não de pessoa física, mas ainda é um dado de contato que não deveria vazar em relatório externo sem necessidade |
| `session_id`, `search_id`, `booking_id`, `cancellation_id` | todas | **Não-PII** | São identificadores de evento/transação, não de pessoa, não permitem reidentificação sozinhos |
| `pickup_location`, `dropoff_location`, `country`, sessão/busca | `raw_searches`, `raw_bookings`, `raw_sessions` | **Não-PII** | Granularidade de cidade/país, não geolocalização precisa |

## 10. Limitações e itens em aberto

- Todos os achados de qualidade encontrados até aqui, múltiplas reservas mesmo usuário/dia, `days_before_pickup` negativo, outliers de `total_amount`, categoria `compact` fora do domínio, sessões maiores que 6h, clique sem resultado, `refund_amount > total_amount`, agora têm teste formal em `severity: warn`, confirmado via `dbt test` real, seção 6, mas continuam **monitorados, não bloqueados ou filtrados** no fato, exceto `refund_amount` e `total_amount<=0`, que já eram filtrados desde o D1. É uma decisão de escopo consciente: são sinais de possível problema, não certezas, e excluir automaticamente arriscaria jogar fora dado legítimo.
- `dim_users` cobre só usuários autenticados, com `user_id`, sessões e reservas 100% anônimas não geram linha de dimensão, ficando nos fatos com `user_id` nulo.
- SLA de dados, seção 8, não está implementado como gate de CI real, é a definição e proposta de threshold, não a automação em si. Automatizar isso, por exemplo pipeline falhar ou alertar quando os thresholds da seção 8.4 forem ultrapassados, é next step natural, fora do escopo de tempo deste case.
