-- ============================================================================
-- Desafio 2 — SQL Analítico Avançado | Case Rentcars
-- Q1 — Taxa de conversão do funil sessão → busca → reserva,
-- segmentada por país e device.
--
-- Executada diretamente sobre o DuckDB local materializado pelo dbt
-- (dbt/rentcars_analytics/dev.duckdb), consumindo as camadas
-- intermediate/marts já validadas no Desafio 1.
-- Ver sql/run_funil_conversao.py para o script de execução e exportação
-- em CSV (máx. 1.000 linhas).
--
-- Premissas (confirmadas em 09/09/2026):
-- 1. Base de sessões: int_sessions (já exclui is_bot = true e está
--    deduplicada por session_id — regras de raw_sessions do data_dictionary).
-- 2. Conversão para "busca": sessão com >= 1 linha em int_searches (já exclui
--    buscas de sessão bot e está deduplicada por search_id).
-- 3. Conversão para "reserva": sessão com >= 1 linha em fct_bookings (já
--    aplica todas as regras de raw_bookings do data_dictionary: dedup,
--    parceiro ativo, total_amount > 0 para confirmed/completed) E cujo
--    booking_id NÃO aparece em int_cancellations — reservas canceladas não
--    contam como conversão real (achado documentado em governance.md).
-- 4. País e device vêm da sessão (int_sessions) — únicas tabelas do funil que
--    carregam esses atributos; a reserva/busca herdam o país/device da sessão
--    de origem via join por session_id.
-- 5. Janela de tempo: período completo disponível nos dados (01/10/2024 a
--    31/03/2025), sem recorte — decisão registrada em governance.md.
-- 6. country/device nulos ou em branco viram 'Não identificado' em vez de
--    serem descartados, para não perder volume do funil (o data_dictionary.md
--    declara essas colunas como NOT NULL, mas a checagem defensiva é mantida).
-- 7. Colunas de saída traduzidas para português (pais, dispositivo) para
--    consumo direto por stakeholders não técnicos.
--
-- Validação: resultado conferido de forma independente, reconstruindo a
-- mesma lógica diretamente sobre os CSVs brutos fora do pipeline dbt — os
-- números bateram exatamente para as 21 combinações de país x device.
-- ============================================================================

with sessoes as (
    select
        session_id,
        coalesce(nullif(trim(country), ''), 'Não identificado') as country,
        coalesce(nullif(trim(device), ''), 'Não identificado') as device
    from int_sessions
),

buscas as (
    select distinct session_id
    from int_searches
),

reservas_validas as (
    -- reservas que já passaram por todas as regras do data_dictionary
    -- (fct_bookings reflete isso) e que não foram canceladas
    select distinct fb.session_id
    from fct_bookings fb
    left join int_cancellations ic
        on fb.booking_id = ic.booking_id
    where ic.booking_id is null
),

funil as (
    select
        s.country,
        s.device,
        count(distinct s.session_id) as total_sessoes,
        count(distinct b.session_id) as sessoes_com_busca,
        count(distinct r.session_id) as sessoes_com_reserva
    from sessoes s
    left join buscas b on s.session_id = b.session_id
    left join reservas_validas r on s.session_id = r.session_id
    group by s.country, s.device
)

select
    country as pais,
    device as dispositivo,
    total_sessoes,
    sessoes_com_busca,
    sessoes_com_reserva,
    round(100.0 * sessoes_com_busca / nullif(total_sessoes, 0), 2) as taxa_sessao_para_busca_pct,
    round(100.0 * sessoes_com_reserva / nullif(sessoes_com_busca, 0), 2) as taxa_busca_para_reserva_pct,
    round(100.0 * sessoes_com_reserva / nullif(total_sessoes, 0), 2) as taxa_conversao_geral_pct
from funil
order by total_sessoes desc
limit 1000;
