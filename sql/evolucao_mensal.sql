

with reservas_validas as (
    select
        fb.*,
        strftime(fb.booked_at, '%Y-%m') as mes_ano
    from fct_bookings fb
    left join int_cancellations ic
        on fb.booking_id = ic.booking_id
    where fb.status in ('confirmed', 'completed')
        and ic.booking_id is null
)

select
    mes_ano,
    count(*) as quantidade_reservas,
    round(sum(case when currency = 'BRL' then total_amount else 0 end), 2) as receita_brl,
    round(sum(case when currency = 'USD' then total_amount else 0 end), 2) as receita_usd,
    round(sum(case when currency = 'ARS' then total_amount else 0 end), 2) as receita_ars,
    round(sum(case when currency = 'CLP' then total_amount else 0 end), 2) as receita_clp,
    round(sum(case when currency = 'COP' then total_amount else 0 end), 2) as receita_cop
from reservas_validas
group by mes_ano
order by mes_ano
limit 1000;
