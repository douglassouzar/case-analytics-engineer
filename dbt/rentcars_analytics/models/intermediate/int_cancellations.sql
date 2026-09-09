with base_cancellations as (
    select * from {{ ref('stg_cancellations') }}
),

base_bookings as (
    select booking_id, total_amount from {{ ref('stg_bookings') }}
),

deduplicacao as (
    select
        c.*,
        b.total_amount as booking_total_amount,
        row_number() over (
            partition by c.cancellation_id
            order by c.cancelled_at desc
        ) as row_num
    from base_cancellations c
    inner join base_bookings b on c.booking_id = b.booking_id
)

select
    cancellation_id,
    booking_id,
    cancelled_at,
    reason,
    cancelled_by,
    refund_amount,
    refund_status,
    days_before_pickup
from deduplicacao
where row_num = 1
    and (refund_amount is null or refund_amount <= booking_total_amount)
