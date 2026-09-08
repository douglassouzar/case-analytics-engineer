with base as (
    select * from {{ source('raw', 'raw_searches') }}
)

select
    search_id,
    session_id,
    cast(searched_at as timestamp) as searched_at,
    trim(pickup_location) as pickup_location,
    trim(dropoff_location) as dropoff_location,
    cast(pickup_date as date) as pickup_date,
    cast(dropoff_date as date) as dropoff_date,
    lower(trim(car_category)) as car_category,
    num_results,
    partner_id_clicked,
    price_shown
from base