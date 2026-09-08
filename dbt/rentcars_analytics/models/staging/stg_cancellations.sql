with base as (
    select * from {{ source('raw', 'raw_cancellations') }}
)

select
    cancellation_id,
    booking_id,
    cast(cancelled_at as timestamp) as cancelled_at,
    lower(trim(reason)) as reason,
    lower(trim(cancelled_by)) as cancelled_by,
    refund_amount,
    lower(trim(refund_status)) as refund_status,
    days_before_pickup
from base