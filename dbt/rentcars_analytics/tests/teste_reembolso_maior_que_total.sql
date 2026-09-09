-- Teste singular (severity: warn).
--
-- data_dictionary.md: "refund_amount não deve ser superior ao total_amount
-- da reserva associada". Já é aplicado como FILTRO em int_cancellations
-- (achado 4.1 do governance.md — regra estava documentada no schema.yml
-- mas não codificada até essa correção). Esse teste roda sobre a camada
-- staging (antes do filtro) para deixar o volume visível a cada dbt test,
-- em vez de só "desaparecer" silenciosamente no int_cancellations filtrado.
--
-- Achado: 794 cancelamentos violam essa regra.

{{ config(severity = 'warn') }}

select
    c.cancellation_id,
    c.booking_id,
    c.refund_amount,
    b.total_amount
from {{ ref('stg_cancellations') }} c
join {{ ref('stg_bookings') }} b on c.booking_id = b.booking_id
where c.refund_amount > b.total_amount
