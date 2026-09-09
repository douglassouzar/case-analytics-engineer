-- Teste singular (severity: warn, config abaixo).
--
-- Regra do data_dictionary.md: "Múltiplas reservas de um mesmo usuário num
-- mesmo dia são atípicas e podem indicar fraude". Não bloqueamos essas
-- reservas no fato (decisão registrada em governance.md), mas o teste
-- garante que o volume fica visível a cada rodada de dbt test, em vez de
-- ficar escondido só num profiling manual.
--
-- Achado na varredura de 09/09/2026: 16 usuários / 34 reservas.

{{ config(severity = 'warn') }}

select
    user_id,
    cast(booked_at as date) as booked_date,
    count(*) as qtd_reservas_no_dia
from {{ ref('int_bookings') }}
where user_id is not null
group by user_id, cast(booked_at as date)
having count(*) > 1
