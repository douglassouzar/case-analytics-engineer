with base as (
    select * from {{ source('raw', 'raw_bookings') }}
)

select
    booking_id,
    session_id,
    user_id,
    partner_id,
    cast(booked_at as timestamp) as booked_at,
    cast(pickup_date as date) as pickup_date,
    cast(dropoff_date as date) as dropoff_date,
    trim(pickup_location) as pickup_location,
    lower(trim(car_category)) as car_category,
    daily_rate,
    total_amount,
    upper(trim(currency)) as currency,
    lower(trim(status)) as status,
    lower(trim(payment_method)) as payment_method
from base