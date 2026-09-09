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
from {{ ref('int_partners') }}
