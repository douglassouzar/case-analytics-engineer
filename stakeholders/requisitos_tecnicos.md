# Requisitos Técnicos — Relatório de Receita por Parceiro (Revenue/Pricing)

> Documento derivado da entrevista de discovery em `roteiro_entrevista.md`, com a Head de Revenue & Pricing. Traduz o que foi combinado em requisito técnico rastreável, para ser a referência usada na implementação e em qualquer questionamento futuro sobre "de onde vem esse número".

## 1. Objetivo

Substituir o processo manual atual (export do sistema transacional + planilha, ~2 dias de trabalho por ciclo) por um relatório recorrente de receita por parceiro, com uma única definição de métrica compartilhada entre Revenue/Pricing, Comercial (board) e Financeiro.

## 2. Mapeamento As-Is → To-Be

| Dimensão | As-Is (hoje) | To-Be (após os modelos dbt deste case) |
|---|---|---|
| **Fonte do dado** | Export manual do sistema transacional de origem | `fct_bookings` + `int_cancellations` + `dim_partners`, já testados e documentados no D1, consumidos via o contrato `rpt_revenue_by_partner` (`data_contract.yaml`) |
| **Processo de obtenção** | Head de Revenue/Pricing exporta manualmente e cruza numa planilha a cada ciclo | Pipeline dbt incremental roda automaticamente; consumidor lê o resultado já pronto, sem etapa manual de extração |
| **Tempo de preparação** | ~2 dias corridos por ciclo | Minutos — tempo de execução do `dbt run` incremental (SLA proposto: rodar a cada 24h, ver `governance.md` seção 8.1) |
| **Definição de receita** | Implícita, refeita "de cabeça" a cada vez que alguém monta a planilha, sem documentação formal | Definição única, versionada e documentada em `data_contract.yaml` (`business_rules.revenue_definition`), a mesma para todos os públicos |
| **Consistência entre pessoas** | Cada pessoa que monta a planilha pode chegar a um número ligeiramente diferente (achado relatado pela própria stakeholder) | Fonte única (`rpt_revenue_by_partner`); qualquer divergência vira pergunta sobre o contrato, não sobre "quem calculou certo" |
| **Frequência** | Trimestral, sem visão intermediária | Mensal oficial (fechado) + visão parcial do mês corrente, ambas geradas pelo mesmo pipeline |
| **Tratamento de multi-moeda** | Não tratado explicitamente — presumivelmente somado sem critério declarado | Aberto por moeda, sem soma indevida entre BRL/USD/ARS/CLP/COP (ver RF-02) |
| **Consolidado único para o board** | Inexistente/informal | Ainda não existe um número único confiável — depende de RF-05 (tabela de câmbio oficial). Ver seção 2.3 |
| **Alerta de qualidade** | Nenhum — problema só aparece quando alguém percebe que o número "não bateu" | Alertas automáticos de completude (RF-04) e de reservas suspeitas (RF-06) publicados junto com o relatório |
| **Formato de consumo** | Planilha isolada, sem versionamento | Dashboard para acompanhamento contínuo + export em planilha no fechamento do mês (RF-07) |
| **Rastreabilidade** | Nenhuma — decisão de cálculo vive só na cabeça de quem monta a planilha | `roteiro_entrevista.md` + este documento + `data_contract.yaml` registram por escrito toda decisão e seu porquê |

## 3. Escopo — Fase 1 (entrega deste ciclo)

### 3.1 Definição de receita (RF-01)

Receita = soma de `total_amount` de `fct_bookings` onde:
- `status in ('confirmed', 'completed')`
- `booking_id` **não** aparece em `int_cancellations`

Esta definição já existe no glossário de métricas do projeto (`governance.md`, seção 7.2) e foi confirmada, sem alteração, pela stakeholder. Não há trabalho novo aqui, é reaproveitamento direto de `fct_bookings`.

### 3.2 Abertura por moeda, sem consolidação forçada (RF-02)

O relatório detalhado (uso de Pricing e Financeiro) reporta receita **aberta por `currency`** — uma coluna/linha por moeda (BRL, USD, ARS, CLP, COP) — nunca somada entre moedas.

**Justificativa:** o dataset não possui tabela de câmbio. Somar valores de moedas diferentes sem taxa de conversão produz um número sem validade financeira e, neste caso, afeta diretamente cálculo de comissão paga a parceiro — um erro aqui tem custo financeiro real, não é só um número de dashboard errado.

### 3.3 Consolidado para o board — sem solução provisória (RF-03, revisado)

**Decisão final da entrevista (atualizada 10/09):** ao contrário de uma versão anterior deste requisito, **não** será produzido nenhum número aproximado/provisório para o board nesta fase. A stakeholder concordou em priorizar a versão correta (RF-05, câmbio oficial) em vez de um número aproximado com aviso — a alternativa de "consolidado aproximado com disclaimer" foi discutida e descartada na negociação final.

**Implicação prática:** até que RF-05 seja entregue, o board recebe a mesma visão aberta por moeda que Pricing e Financeiro usam (RF-02), sem um número único de receita total. Isso deve ser comunicado explicitamente ao diretor comercial antes da primeira reunião de board que usar este relatório, para não gerar expectativa de um número que não existe ainda.

**Sem prazo definido para RF-05:** a própria stakeholder reconheceu que a solução definitiva depende de outro time (engenharia de dados) e não quis se comprometer com uma data nesta rodada. Tratado como item de backlog em aberto, não como uma entrega desta fase (ver seção 4).

### 3.4 Alerta de completude de receita (RF-04)

O relatório mensal deve reportar, junto com a receita, o volume de reservas `confirmed`/`completed` excluídas do cálculo por `total_amount` nulo, zerado ou negativo, com o percentual sobre o total de reservas confirmadas/concluídas do mês.

**Threshold de alerta:** se esse percentual ultrapassar ~2% no mês (linha de base atual: 297 reservas com valor nulo + 156 com valor inválido, sobre a base histórica total), o relatório deve destacar isso como anomalia a investigar, não apenas reportar o número como se fosse normal. Threshold consistente com o já definido em `governance.md`, seção 8.2.

### 3.5 Sinalização de reservas suspeitas (RF-06)

O relatório deve incluir uma seção separada (não misturada ao número de receita oficial) listando parceiros/períodos com reservas suspeitas de múltiplas reservas do mesmo usuário no mesmo dia (`teste_reservas_duplicadas_usuario_dia`, já existente em `governance.md`, seção 3). Não remove nada da receita automaticamente — é sinalização para revisão humana antes de qualquer ação sobre comissão.

**Threshold de alerta:** consistente com `governance.md`, seção 8.4 — alerta se ultrapassar 0,5% dos usuários com reserva no período.

### 3.6 Frequência e formato (RF-07)

- Fechamento mensal oficial: número final, gerado após o mês fechado, usado para reunião de revisão de comissão.
- Visão parcial: número acumulado do mês corrente, atualizado com a mesma cadência do incremental de `fct_bookings` (ver SLA de freshness em `governance.md`, seção 8.1), claramente identificado como **parcial, sujeito a alteração**.
- Formato: dashboard para acompanhamento contínuo (Pricing e board) + export em planilha gerado no fechamento do mês (uso em reunião de comissão com parceiro, permite anotação manual por cima).

## 4. Fora de escopo desta fase (backlog)

| Item | Motivo de não entrar agora | Próximo passo proposto |
|---|---|---|
| **RF-05 — Conversão cambial oficial / consolidado único para o board** | Requer nova fonte de dado (tabela de câmbio histórica) e modelo novo no dbt; depende de coordenação com outro time (engenharia de dados); **sem prazo definido**, conforme a própria stakeholder reconheceu na entrevista | Incorporar cotação diária do Banco Central do Brasil (`dadosabertos.bcb.gov.br`, dataset "Taxas de Câmbio, todos os boletins diários", API OData, cobre BRL/USD/ARS/CLP/COP), com decisão pendente sobre data de referência da conversão (data da reserva vs. data de fechamento do mês) |
| **Receita líquida de reembolso parcial** | `fct_bookings` guarda valor bruto da reserva; reembolso mora em `int_cancellations`, não há join pronto para isso | Novo modelo intermediate que combina `total_amount` com `refund_amount` quando existente, antes de entrar no cálculo de receita |

## 5. Critérios de aceite

1. O número de receita detalhado (por moeda, por parceiro) bate, sem ajuste manual, com uma reconciliação independente feita pelo Financeiro em pelo menos um ciclo de fechamento.
2. O board é informado, antes da primeira apresentação, de que não existe ainda um número único consolidado de receita — apenas a visão aberta por moeda — até que RF-05 seja entregue.
3. O relatório sinaliza automaticamente quando o volume de reservas com valor inválido ou reservas suspeitas ultrapassa os thresholds definidos (seções 3.4 e 3.5), sem que a stakeholder precise descobrir isso manualmente.
4. A definição de receita usada é a mesma em todos os públicos (Pricing, board, Financeiro) — não existe uma segunda definição paralela em nenhuma planilha.

## 6. Rastreabilidade

Este documento formaliza os acordos da entrevista em `roteiro_entrevista.md`. O contrato de dados correspondente à entrega (schema, dono, SLA, regras de qualidade, e o catálogo de métricas por item) está em `data_contract.yaml`, mesma pasta.
