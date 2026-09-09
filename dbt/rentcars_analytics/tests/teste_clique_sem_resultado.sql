-- Teste singular (severity: warn).
--
-- Inconsistência lógica entre duas colunas da mesma linha: o usuário
-- "clicou" num parceiro (partner_id_clicked preenchido) numa busca que,
-- segundo o dado, retornou zero resultados (num_results = 0). Não é uma
-- regra explícita do data_dictionary.md, mas é um sinal de possível
-- problema de instrumentação do evento de clique — vale monitorar.
--
-- Achado na varredura de 09/09/2026: 1.197 buscas nessa condição.

{{ config(severity = 'warn') }}

select
    search_id,
    session_id,
    num_results,
    partner_id_clicked
from {{ ref('int_searches') }}
where num_results = 0
    and partner_id_clicked is not null
