-- Teste singular (severity: warn).
--
-- data_dictionary.md: "sessões são encerradas após 30 min de inatividade" e
-- "a duração típica de uma sessão não ultrapassa algumas horas". Sessões
-- muito longas contrariam essa expectativa na prática — não é uma regra de
-- negócio com um número oficial ("algumas horas" é vago), então usamos 6h
-- como limiar de monitoramento (bem acima da mediana observada de ~30min e
-- do p75 de ~45min no profiling), documentado em governance.md seção 8 (SLA).
--
-- Achado na varredura de 09/09/2026: 589 sessões acima de 6h, a mais longa
-- com quase 72h.

{{ config(severity = 'warn') }}

select
    session_id,
    started_at,
    ended_at,
    date_diff('hour', started_at, ended_at) as duracao_horas
from {{ ref('int_sessions') }}
where ended_at is not null
    and date_diff('hour', started_at, ended_at) > 6
