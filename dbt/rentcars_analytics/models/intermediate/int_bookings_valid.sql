with base as (
    select * from {{ ref('stg_bookings') }}
),

parceiros_ativos as (
    select partner_id
    from {{ ref('stg_partners') }}
    where status = 'active'
),

deduplicacao as (
    select
        b.*,
        row_number() over (
            partition by b.booking_id
            order by b.booked_at desc
        ) as row_num
    from base b
    inner join parceiros_ativos p on b.partner_id = p.partner_id
)

select
    booking_id,
    session_id,
    user_id,
    partner_id,
    booked_at,
    pickup_date,
    dropoff_date,
    pickup_location,
    car_category,
    daily_rate,
    total_amount,
    currency,
    status,
    payment_method
from deduplicacao
where row_num = 1
    and (total_amount > 0 or status not in ('confirmed', 'completed'))