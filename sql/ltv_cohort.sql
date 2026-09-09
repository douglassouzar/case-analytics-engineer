-- ============================================================================
-- Desafio 2 — SQL Analítico Avançado | Case Rentcars
-- Q3 — LTV (Lifetime Value) médio dos usuários, agrupado por cohort de
-- primeiro acesso (mês/ano), aberto por moeda.
--
-- Executada diretamente sobre o DuckDB local materializado pelo dbt
-- (dbt/rentcars_analytics/dev.duckdb), consumindo as camadas
-- intermediate/marts já validadas no Desafio 1.
-- Ver sql/run_ltv_cohort.py para o script de execução e exportação em CSV.
--
-- Premissas (confirmadas em 10/09/2026):
-- 1. LTV = receita acumulada de cada usuário dentro do período disponível
--    nos dados (não é contagem de sessões nem tempo até reservar — é a
--    aproximação de "valor gerado até aqui", já que o dataset não cobre o
--    ciclo de vida completo do cliente).
-- 2. Reserva válida para efeito de receita: mesma regra de duas camadas da
--    Q2 — status in ('confirmed', 'completed') em fct_bookings E
--    booking_id fora de int_cancellations.
-- 3. Sem corte de janela temporal (diferente da Q2): soma todo o período
--    disponível nos dados.
-- 4. Aberto por moeda (mesmo motivo da Q2: parceiros/reservas nas 5 moedas
--    presentes na base, sem tabela de câmbio disponível para converter).
-- 5. Cohort = mês/ano de first_seen_at (primeira sessão) em dim_users.
--    Usuários com first_seen_at nulo (aparecem em reservas mas nunca
--    tiveram sessão válida registrada) ficam fora da análise de cohort —
--    achado quantificado e documentado em governance.md.
-- 6. Usuários anônimos (sem user_id) ficam de fora, já que dim_users só
--    cobre usuários autenticados/identificáveis.
-- 7. Métrica reportada é a MÉDIA de LTV por usuário em cada cohort — e o
--    denominador é TODOS os usuários da cohort (inclusive os que nunca
--    reservaram, contados como LTV = 0), não só os que compraram. Isso
--    reflete o valor médio real gerado pela cohort inteira, e não apenas
--    pelos usuários pagantes.
-- ============================================================================

with bookings_receita as (
    -- reservas que geram receita segundo o glossário do case
    select *
    from fct_bookings
    where status in ('confirmed', 'completed')
),

bookings_validas as (
    -- remove as que tiveram evento de cancelamento registrado
    select b.*
    from bookings_receita b
    left join int_cancellations ic
        on b.booking_id = ic.booking_id
    where ic.booking_id is null
),

ltv_por_usuario as (
    select
        user_id,
        sum(case when currency = 'BRL' then total_amount else 0 end) as ltv_brl,
        sum(case when currency = 'USD' then total_amount else 0 end) as ltv_usd,
        sum(case when currency = 'ARS' then total_amount else 0 end) as ltv_ars,
        sum(case when currency = 'CLP' then total_amount else 0 end) as ltv_clp,
        sum(case when currency = 'COP' then total_amount else 0 end) as ltv_cop
    from bookings_validas
    where user_id is not null
    group by user_id
),

usuarios_cohort as (
    select
        user_id,
        strftime(first_seen_at, '%Y-%m') as cohort_mes_ano
    from dim_users
    where first_seen_at is not null
)

select
    c.cohort_mes_ano,
    count(distinct c.user_id) as quantidade_usuarios,
    round(avg(coalesce(l.ltv_brl, 0)), 2) as ltv_medio_brl,
    round(avg(coalesce(l.ltv_usd, 0)), 2) as ltv_medio_usd,
    round(avg(coalesce(l.ltv_ars, 0)), 2) as ltv_medio_ars,
    round(avg(coalesce(l.ltv_clp, 0)), 2) as ltv_medio_clp,
    round(avg(coalesce(l.ltv_cop, 0)), 2) as ltv_medio_cop
from usuarios_cohort c
left join ltv_por_usuario l on c.user_id = l.user_id
group by c.cohort_mes_ano
order by c.cohort_mes_ano
limit 1000;
