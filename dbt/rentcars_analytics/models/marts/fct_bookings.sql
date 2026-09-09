{{
    config(
        materialized='incremental',
        unique_key='booking_id',
        incremental_strategy='delete+insert'
    )
}}

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
from {{ ref('int_bookings') }}

{% if is_incremental() %}
where booked_at > (select max(booked_at) from {{ this }})
{% endif %}