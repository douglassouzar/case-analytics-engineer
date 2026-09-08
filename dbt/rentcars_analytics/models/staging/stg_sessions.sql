with base as (
    select * from {{ source('raw', 'raw_sessions') }}
)

select
    session_id,
    user_id,
    cast(started_at as timestamp) as started_at,
    cast(ended_at as timestamp) as ended_at,
    lower(trim(channel)) as channel,
    lower(trim(device)) as device,
    upper(trim(country)) as country,
    page_views,
    lower(trim(utm_source)) as utm_source,
    lower(trim(utm_campaign)) as utm_campaign,
    is_bot
from base