with base_searches as (
    select * from {{ ref('stg_searches') }}
),

base_sessions as (
    select session_id from {{ ref('stg_sessions') }}
),

deduplicacao as (
    select
        s.*,
        row_number() over (
            partition by s.search_id
            order by s.searched_at desc
        ) as row_num
    from base_searches s
    inner join base_sessions ss on s.session_id = ss.session_id
)

select
    search_id,
    session_id,
    searched_at,
    pickup_location,
    dropoff_location,
    pickup_date,
    dropoff_date,
    car_category,
    num_results,
    partner_id_clicked,
    price_shown
from deduplicacao
where row_num = 1
