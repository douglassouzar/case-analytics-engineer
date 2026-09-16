with sessoes as (
    select session_id
    from int_sessions
),

buscas as (
    select distinct session_id
    from int_searches
),

reservas_validas as (
    select distinct fb.session_id
    from fct_bookings fb
    left join int_cancellations ic
        on fb.booking_id = ic.booking_id
    where ic.booking_id is null
),

totais as (
    select
        count(distinct s.session_id) as total_sessoes,
        count(distinct b.session_id) as total_buscas,
        count(distinct r.session_id) as total_reservas
    from sessoes s
    left join buscas b on s.session_id = b.session_id
    left join reservas_validas r on s.session_id = r.session_id
)

select 'Sessões' as etapa, 1 as ordem, total_sessoes as valor from totais
union all
select 'Buscas' as etapa, 2 as ordem, total_buscas as valor from totais
union all
select 'Reservas' as etapa, 3 as ordem, total_reservas as valor from totais
order by ordem;
