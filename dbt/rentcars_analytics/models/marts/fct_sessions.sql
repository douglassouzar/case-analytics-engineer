{{
    config(
        materialized='incremental',
        unique_key='session_id',
        incremental_strategy='delete+insert'
    )
}}

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
from {{ ref('int_sessions_deduped') }}

{% if is_incremental() %}
where started_at > (select max(started_at) from {{ this }})
{% endif %}