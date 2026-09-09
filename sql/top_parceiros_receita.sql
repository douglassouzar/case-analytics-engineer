-- ============================================================================
-- Desafio 2 — SQL Analítico Avançado | Case Rentcars
-- Q2 — Top 10 parceiros por volume de reservas nos últimos 90 dias,
-- excluindo cancelamentos, com receita aberta por moeda.
--
-- Executada diretamente sobre o DuckDB local materializado pelo dbt
-- (dbt/rentcars_analytics/dev.duckdb), consumindo as camadas
-- intermediate/marts já validadas no Desafio 1.
-- Ver sql/run_receita_parceiros.py para o script de execução e exportação
-- em CSV (máx. 1.000 linhas — aqui o "top 10" já garante isso).
--
-- Premissas (confirmadas em 09-10/09/2026):
-- 1. Janela "últimos 90 dias": referência é a maior data presente em
--    fct_bookings (max(booked_at), calculada em CTE), já que não há uma
--    data de "hoje" real no dataset.
-- 2. Verificação em DUAS camadas antes de contar uma reserva (regra
--    registrada em governance.md):
--    a) 1ª camada: apenas status in ('confirmed', 'completed') em
--       fct_bookings — segue o glossário do data_dictionary.md ("Reserva
--       gera receita quando status = confirmed ou completed") e evita
--       somar total_amount de pending/no_show, cujo valor não é validado
--       pela regra de negócio.
--    b) 2ª camada: remove qualquer booking_id que apareça em
--       int_cancellations, mesmo que o status em fct_bookings não tenha
--       sido atualizado.
-- 3. MUDANÇA DE ESCOPO relevante: a receita NÃO é somada numa única coluna.
--    Achado durante a construção: os 20 parceiros do dataset têm reservas
--    nas 5 moedas presentes (BRL, USD, ARS, CLP, COP), e o dataset não
--    inclui tabela de câmbio — somar total_amount entre moedas produziria
--    um número financeiramente sem sentido. Solução adotada: abrir a
--    receita em uma coluna por moeda (total_BRL, total_USD, total_ARS,
--    total_CLP, total_COP), sem conversão. Solicitação de tabela de
--    câmbio (ex: BCB) registrada em governance.md para uma iteração futura.
-- 4. "Top 10 parceiros": ordenado por quantidade_reservas decrescente
--    (única métrica comparável entre parceiros sem conversão de moeda),
--    com empate desempatado por total_BRL decrescente — BRL assumido como
--    moeda do mercado principal da operação (decisão registrada em
--    governance.md).
-- ============================================================================

with data_limite as (
    select max(booked_at) as max_booked_at
    from fct_bookings
),

-- 1ª camada: só reservas que geram receita segundo o glossário do case
bookings_receita as (
    select fb.*
    from fct_bookings fb
    cross join data_limite d
    where fb.booked_at >= d.max_booked_at - interval 90 day
        and fb.status in ('confirmed', 'completed')
),

-- 2ª camada: remove as que tiveram evento de cancelamento registrado
bookings_validas as (
    select b.*
    from bookings_receita b
    left join int_cancellations ic
        on b.booking_id = ic.booking_id
    where ic.booking_id is null
),

receita_por_parceiro_moeda as (
    select
        b.partner_id,
        count(*) as quantidade_reservas,
        sum(case when b.currency = 'BRL' then b.total_amount else 0 end) as total_brl,
        sum(case when b.currency = 'USD' then b.total_amount else 0 end) as total_usd,
        sum(case when b.currency = 'ARS' then b.total_amount else 0 end) as total_ars,
        sum(case when b.currency = 'CLP' then b.total_amount else 0 end) as total_clp,
        sum(case when b.currency = 'COP' then b.total_amount else 0 end) as total_cop
    from bookings_validas b
    group by b.partner_id
)

select
    p.partner_name as parceiro,
    r.quantidade_reservas,
    round(r.total_brl, 2) as total_brl,
    round(r.total_usd, 2) as total_usd,
    round(r.total_ars, 2) as total_ars,
    round(r.total_clp, 2) as total_clp,
    round(r.total_cop, 2) as total_cop
from receita_por_parceiro_moeda r
join dim_partners p on r.partner_id = p.partner_id
order by r.quantidade_reservas desc, r.total_brl desc
limit 10;
