-- Teste singular (severity: warn).
--
-- data_dictionary.md: "Valores de total_amount muito acima do padrão da
-- categoria devem ser investigados". Método: IQR (1.5x) por car_category,
-- só em reservas confirmed/completed (mesmo universo usado no filtro de
-- receita) — mesmo critério estatístico usado na Q5 do Desafio 2 (lá foi
-- 2-sigma sobre taxas agregadas; aqui é IQR sobre valores individuais,
-- técnica mais robusta a outliers extremos do que média/desvio-padrão).
--
-- Achado na varredura de 09/09/2026: ~101 outliers no total, com destaque
-- para pickup (22 outliers, máx. R$79.311 vs. limite ~R$7.901) e economy
-- (9 outliers, máx. R$77.361 vs. limite ~R$7.953).

{{ config(severity = 'warn') }}

with base as (
    select
        booking_id,
        coalesce(car_category, '(nulo)') as car_category,
        total_amount
    from {{ ref('int_bookings') }}
    where status in ('confirmed', 'completed')
        and total_amount > 0
),

quartis as (
    select
        car_category,
        percentile_cont(0.25) within group (order by total_amount) as q1,
        percentile_cont(0.75) within group (order by total_amount) as q3
    from base
    group by car_category
),

limites as (
    select
        car_category,
        q3 + 1.5 * (q3 - q1) as limite_superior
    from quartis
)

select
    b.booking_id,
    b.car_category,
    b.total_amount,
    l.limite_superior
from base b
join limites l on b.car_category = l.car_category
where b.total_amount > l.limite_superior
