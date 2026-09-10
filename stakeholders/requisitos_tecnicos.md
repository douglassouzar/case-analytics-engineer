# Requisitos Técnicos — Relatório de Receita por Parceiro (Revenue/Pricing)

> Documento derivado da entrevista de discovery em `roteiro_entrevista.md`, com o Head de Revenue & Pricing. Traduz o que foi combinado em requisito técnico rastreável, para ser a referência usada na implementação e em qualquer questionamento futuro sobre "de onde vem esse número".

## 1. Objetivo

Substituir o processo manual atual (export do sistema transacional + planilha, ~2 dias de trabalho por ciclo) por um relatório recorrente de receita por parceiro, com uma única definição de métrica compartilhada entre Revenue/Pricing, Comercial (board) e Financeiro.

## 2. Escopo — Fase 1 (entrega deste ciclo)

### 2.1 Definição de receita (RF-01)

Receita = soma de `total_amount` de `fct_bookings` onde:
- `status in ('confirmed', 'completed')`
- `booking_id` **não** aparece em `int_cancellations`

Esta definição já existe no glossário de métricas do projeto (`governance.md`, seção 7.2) e foi confirmada, sem alteração, pela stakeholder. Não há trabalho novo aqui, é reaproveitamento direto de `fct_bookings`.

### 2.2 Abertura por moeda, sem consolidação forçada (RF-02)

O relatório detalhado (uso de Pricing e Financeiro) reporta receita **aberta por `currency`** — uma coluna/linha por moeda (BRL, USD, ARS, CLP, COP) — nunca somada entre moedas.

**Justificativa:** o dataset não possui tabela de câmbio. Somar valores de moedas diferentes sem taxa de conversão produz um número sem validade financeira e, neste caso, afeta diretamente cálculo de comissão paga a parceiro — um erro aqui tem custo financeiro real, não é só um número de dashboard errado.

**Fora de escopo desta fase:** conversão cambial automatizada. Ver RF-05.

### 2.3 Consolidado aproximado para o board (RF-03)

Para a visão de board (não usada para cálculo de comissão), o relatório pode apresentar um valor único aproximado em BRL, usando uma taxa de câmbio fixa de referência definida manualmente a cada ciclo pelo time de Revenue/Pricing, **até que RF-05 seja implementado**.

**Obrigatório:** todo número gerado por esta regra deve carregar, no mesmo relatório, um aviso visível do tipo "valor aproximado, taxa de câmbio fixa de referência, não usar para cálculo de comissão" — nunca apresentado sem esse aviso.

### 2.4 Alerta de completude de receita (RF-04)

O relatório mensal deve reportar, junto com a receita, o volume de reservas `confirmed`/`completed` excluídas do cálculo por `total_amount` nulo, zerado ou negativo, com o percentual sobre o total de reservas confirmadas/concluídas do mês.

**Threshold de alerta:** se esse percentual ultrapassar ~2% no mês (linha de base atual: 297 reservas com valor nulo + 156 com valor inválido, sobre a base histórica total), o relatório deve destacar isso como anomalia a investigar, não apenas reportar o número como se fosse normal. Threshold consistente com o já definido em `governance.md`, seção 8.2.

### 2.5 Sinalização de reservas suspeitas (RF-06)

O relatório deve incluir uma seção separada (não misturada ao número de receita oficial) listando parceiros/períodos com reservas suspeitas de múltiplas reservas do mesmo usuário no mesmo dia (`teste_reservas_duplicadas_usuario_dia`, já existente em `governance.md`, seção 3). Não remove nada da receita automaticamente — é sinalização para revisão humana antes de qualquer ação sobre comissão.

**Threshold de alerta:** consistente com `governance.md`, seção 8.4 — alerta se ultrapassar 0,5% dos usuários com reserva no período.

### 2.6 Frequência e formato (RF-07)

- Fechamento mensal oficial: número final, gerado após o mês fechado, usado para reunião de revisão de comissão.
- Visão parcial: número acumulado do mês corrente, atualizado com a mesma cadência do incremental de `fct_bookings` (ver SLA de freshness em `governance.md`, seção 8.1), claramente identificado como **parcial, sujeito a alteração**.
- Formato: dashboard para acompanhamento contínuo (Pricing e board) + export em planilha gerado no fechamento do mês (uso em reunião de comissão com parceiro, permite anotação manual por cima).

## 3. Fora de escopo desta fase (backlog)

| Item | Motivo de não entrar agora | Próximo passo proposto |
|---|---|---|
| **RF-05 — Conversão cambial oficial** | Requer nova fonte de dado (tabela de câmbio histórica) e modelo novo no dbt; não é reaproveitamento do D1 | Incorporar cotação diária do Banco Central do Brasil (`dadosabertos.bcb.gov.br`, dataset "Taxas de Câmbio, todos os boletins diários", API OData, cobre BRL/USD/ARS/CLP/COP), com decisão pendente sobre data de referência da conversão (data da reserva vs. data de fechamento do mês) |
| **Receita líquida de reembolso parcial** | `fct_bookings` guarda valor bruto da reserva; reembolso mora em `int_cancellations`, não há join pronto para isso | Novo modelo intermediate que combina `total_amount` com `refund_amount` quando existente, antes de entrar no cálculo de receita |

## 4. Critérios de aceite

1. O número de receita detalhado (por moeda, por parceiro) bate, sem ajuste manual, com uma reconciliação independente feita pelo Financeiro em pelo menos um ciclo de fechamento.
2. Nenhum número do dashboard do board é usado para cálculo de comissão sem o aviso de aproximação explícito.
3. O relatório sinaliza automaticamente quando o volume de reservas com valor inválido ou reservas suspeitas ultrapassa os thresholds definidos (seções 2.4 e 2.5), sem que a stakeholder precise descobrir isso manualmente.
4. A definição de receita usada é a mesma em todos os públicos (Pricing, board, Financeiro) — não existe uma segunda definição paralela em nenhuma planilha.

## 5. Rastreabilidade

Este documento formaliza os acordos da entrevista em `roteiro_entrevista.md`. O contrato de dados correspondente à entrega (schema, dono, SLA, regras de qualidade) está em `data_contract.yaml`, mesma pasta.
