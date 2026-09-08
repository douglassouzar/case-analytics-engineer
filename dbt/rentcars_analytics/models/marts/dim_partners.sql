with base as (
    select * from {{ ref('stg_partners') }}
),

deduplicacao as (
    select
        *,
        row_number() over (
            partition by partner_id
            order by coalesce(updated_at, created_at) desc
        ) as row_num
    from base
)

select
    partner_id,
    partner_name,
    country,
    tier,
    status,
    commission_rate,
    created_at,
    updated_at,
    contact_email
from deduplicacao
where row_num = 1