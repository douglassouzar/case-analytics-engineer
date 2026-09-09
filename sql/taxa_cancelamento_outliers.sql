-- ============================================================================
-- Desafio 2 — SQL Analítico Avançado | Case Rentcars
-- Q5 — Taxa de cancelamento por parceiro, com identificação de outliers
-- estatísticos (> 2 desvios-padrão da média).
--
-- Executada diretamente sobre o DuckDB local materializado pelo dbt
-- (dbt/rentcars_analytics/dev.duckdb), consumindo as camadas
-- intermediate/marts já validadas no Desafio 1.
-- Ver sql/run_taxa_cancelamento_outliers.py para o script de execução e
-- exportação em CSV.
--
-- Premissas (confirmadas em 10/09/2026):
-- 1. Taxa de cancelamento do parceiro = cancelamentos das reservas do
--    parceiro (via int_cancellations) / reservas do parceiro com status
--    in ('confirmed', 'completed') — segue o glossário do
--    data_dictionary.md, incluindo completed no denominador (confirmado
--    explicitamente pelo usuário).
-- 2. Outlier estatístico: aplicado sobre a DISTRIBUIÇÃO das taxas de
--    cancelamento entre os parceiros (não sobre contagem bruta de
--    cancelamentos) — calcula média e desvio-padrão (populacional) das
--    taxas de todos os parceiros, e marca como outlier qualquer parceiro
--    cuja taxa esteja acima de média + 2*desvio_padrão. Também reporta o
--    limite inferior (média - 2*desvio_padrão) por completude estatística,
--    embora o caso peça especificamente outliers "para cima".
-- 3. Sem corte de janela temporal — soma o período inteiro disponível nos
--    dados (mesmo critério da Q3).
--
-- Explicação do método (para referência técnica futura, ver também
-- sql/results/q5_outliers.png para o gráfico correspondente):
-- Assumindo que as taxas de cancelamento dos parceiros seguem uma
-- distribuição aproximadamente normal, ~95% dos valores devem cair dentro
-- de 2 desvios-padrão da média (regra empírica / "regra 68-95-99.7" de
-- distribuições normais). Um parceiro cuja taxa ultrapassa média + 2σ
-- está, portanto, fora do padrão estatisticamente esperado do grupo — um
-- sinal para investigação (não necessariamente fraude, mas atípico o
-- suficiente para não ser só variação aleatória).
-- ============================================================================

with reservas_validas as (
    select
        partner_id,
        count(*) as qtd_reservas_confirmed_completed
    from fct_bookings
    where status in ('confirmed', 'completed')
    group by partner_id
),

cancelamentos_por_parceiro as (
    select
        b.partner_id,
        count(*) as qtd_cancelamentos
    from int_cancellations c
    join fct_bookings b on c.booking_id = b.booking_id
    group by b.partner_id
),

taxas as (
    select
        r.partner_id,
        r.qtd_reservas_confirmed_completed,
        coalesce(c.qtd_cancelamentos, 0) as qtd_cancelamentos,
        100.0 * coalesce(c.qtd_cancelamentos, 0) / r.qtd_reservas_confirmed_completed as taxa_cancelamento_pct
    from reservas_validas r
    left join cancelamentos_por_parceiro c on r.partner_id = c.partner_id
),

estatisticas as (
    select
        avg(taxa_cancelamento_pct) as media_pct,
        stddev_pop(taxa_cancelamento_pct) as desvio_padrao_pct
    from taxas
)

select
    p.partner_name as parceiro,
    t.qtd_reservas_confirmed_completed as quantidade_reservas,
    t.qtd_cancelamentos as quantidade_cancelamentos,
    round(t.taxa_cancelamento_pct, 2) as taxa_cancelamento_pct,
    round(e.media_pct, 2) as media_geral_pct,
    round(e.desvio_padrao_pct, 2) as desvio_padrao_pct,
    round(e.media_pct + 2 * e.desvio_padrao_pct, 2) as limite_superior_2sigma,
    (t.taxa_cancelamento_pct > e.media_pct + 2 * e.desvio_padrao_pct) as eh_outlier
from taxas t
join dim_partners p on t.partner_id = p.partner_id
cross join estatisticas e
order by t.taxa_cancelamento_pct desc
limit 1000;
