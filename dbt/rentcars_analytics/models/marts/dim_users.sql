with usuarios_sessoes as (
    select distinct user_id from {{ ref('int_sessions') }}
    where user_id is not null
),

usuarios_reservas as (
    select distinct user_id from {{ ref('int_bookings') }}
    where user_id is not null
),

todos_usuarios as (
    select user_id from usuarios_sessoes
    union
    select user_id from usuarios_reservas
),

primeira_sessao as (
    select
        user_id,
        min(started_at) as first_seen_at
    from {{ ref('int_sessions') }}
    where user_id is not null
    group by user_id
)

select
    u.user_id,
    p.first_seen_at
from todos_usuarios u
left join primeira_sessao p on u.user_id = p.user_id