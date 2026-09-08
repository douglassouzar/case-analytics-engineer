with base as (
    select * from {{ ref('stg_sessions') }}
    where is_bot = false
),

deduplicacao as (
    select
        *,
        row_number() over (
            partition by session_id
            order by started_at desc
        ) as row_num
    from base
)

select
    session_id,
    user_id,
    started_at,
    ended_at,
    channel,
    device,
    country,
    page_views,
    utm_source,
    utm_campaign
from deduplicacao
where row_num = 1