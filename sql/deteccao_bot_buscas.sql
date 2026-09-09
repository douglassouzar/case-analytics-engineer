-- ============================================================================
-- Desafio 2 — SQL Analítico Avançado | Case Rentcars
-- Q4 — Detecção de sessões suspeitas de bot: mais de 50 buscas em uma
-- janela de 5 minutos.
--
-- Executada diretamente sobre o DuckDB local materializado pelo dbt
-- (dbt/rentcars_analytics/dev.duckdb), consumindo a camada staging
-- (propositalmente, ver premissa 1).
-- Ver sql/run_deteccao_bot_buscas.py para o script de execução e
-- exportação em CSV.
--
-- Premissas (confirmadas em 10/09/2026):
-- 1. Base: stg_searches + stg_sessions (staging, SEM o filtro de is_bot
--    que já existe em int_searches/int_sessions) — de propósito, porque o
--    objetivo desta query é justamente comparar o comportamento
--    encontrado por volume contra a flag is_bot já existente, então
--    filtrar bot de antemão esconderia exatamente o que queremos medir.
-- 2. Janela FIXA de 5 minutos (não deslizante), por simplicidade e menor
--    complexidade de query — decisão tomada conscientemente mesmo sabendo
--    que uma janela deslizante captura rajadas que cruzam a borda de um
--    bloco fixo. Validado que essa simplificação não afeta o resultado
--    neste dataset: a 2ª sessão com mais buscas no total tem apenas 7
--    buscas (muito abaixo do limiar de 50), então não há caso de rajada
--    real dividida entre dois blocos de 5 min que a janela fixa deixaria
--    passar.
-- 3. Resultado traz, por sessão suspeita: o pico de buscas em uma única
--    janela de 5 min e a flag is_bot original — permitindo, com uma única
--    query, responder duas perguntas: (a) quais sessões são suspeitas por
--    volume, e (b) quantas dessas já estavam marcadas como bot vs.
--    quantas escaparam da flag (achado documentado em governance.md).
-- ============================================================================

with buscas_por_janela as (
    select
        session_id,
        time_bucket(interval 5 minute, searched_at) as janela_5min,
        count(*) as qtd_buscas_na_janela
    from stg_searches
    group by session_id, time_bucket(interval 5 minute, searched_at)
),

sessoes_suspeitas as (
    select
        session_id,
        max(qtd_buscas_na_janela) as pico_buscas_5min
    from buscas_por_janela
    group by session_id
    having max(qtd_buscas_na_janela) > 50
)

select
    su.session_id,
    su.pico_buscas_5min,
    s.is_bot as ja_marcada_como_bot,
    case
        when s.is_bot then 'flag is_bot já detectou'
        else 'escapou da flag is_bot'
    end as status_deteccao
from sessoes_suspeitas su
join stg_sessions s on su.session_id = s.session_id
order by su.pico_buscas_5min desc
limit 1000;
