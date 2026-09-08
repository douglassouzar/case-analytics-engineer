with base as (
    select * from {{ source('raw', 'raw_partners') }}
)

    select
        partner_id,
        partner_name,
        upper(trim(country)) as country,
        lower(trim(tier)) as tier,
        lower(trim(status)) as status,
        commission_rate,
        cast(created_at as timestamp) as created_at,
        cast(updated_at as timestamp) as updated_at,
        lower(trim(contact_email)) as contact_email
    from base
