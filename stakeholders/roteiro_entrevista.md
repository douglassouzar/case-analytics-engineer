# Entrevista com Stakeholder: Revenue/Pricing

## Contexto do exercício

Este documento simula uma entrevista de discovery completa com uma stakeholder da área de **Revenue/Pricing** da Rentcars, que pediu um novo relatório recorrente de receita. A simulação usa os marts e achados reais do D1/D2/D4 deste case (`dim_partners`, `fct_bookings`, `governance.md`) como base de tudo que é dito do lado técnico, para que o conflito de métrica levantado seja real, não um exemplo genérico.

**Persona:** Head de Revenue & Pricing.
**Pedido inicial:** "Relatório mensal de receita por parceiro pra apoiar as reuniões de revisão de comissão."

---

## Parte 1 — Contexto e objetivo de negócio

**Eu:** Antes de entrar em qualquer campo ou métrica, queria entender o objetivo por trás do pedido. Pra que decisão esse relatório vai servir?

**Head:** A gente faz revisão trimestral de comissão com os parceiros, tipo Localiza, Hertz, os majors. Hoje eu monto isso manualmente puxando export do sistema transacional e cruzando numa planilha, leva quase 2 dias e sempre tem alguém achando um número diferente do meu. Eu queria um relatório mensal, não só trimestral, pra conseguir antecipar tendência antes da reunião com o parceiro, tipo "esse mês a receita com a TopDrive caiu 15%, por quê?".

**Eu:** E quem mais usa esse número além de você? Pergunto porque muda o nível de detalhe e a tolerância a erro.

**Head:** O diretor comercial olha o total consolidado numa reunião de board mensal. Meu time de pricing usa o detalhado por parceiro pra decidir se ajusta a taxa de comissão de alguém. E o financeiro cruza com o que foi faturado, então pra eles importa muito que bata com o que já está reportado.

**Eu:** Isso já muda uma coisa importante: são pelo menos três públicos com necessidades diferentes, o board quer um número, vocês querem detalhe por parceiro, financeiro quer conciliação. Vou guardar isso pra decidir formato mais na frente.

---

## Parte 2 — Definição da métrica

**Eu:** Quando você diz "receita", o que exatamente entra nesse número? Reserva feita, reserva paga, reserva concluída?

**Head:** Pra mim é o valor da reserva que efetivamente vai gerar comissão. Então reserva cancelada não conta, óbvio. Reserva só "pendente" também não, porque pode nunca virar dinheiro de verdade.

**Eu:** Certo, isso bate com o que já documentei no glossário de métricas do projeto: receita considera reserva com status `confirmed` ou `completed`, e eu também tiro qualquer reserva que apareça depois em cancelamento, mesmo que o status ainda não tenha sido atualizado no sistema de origem. 

**Eu:** Outra dúvida, como é a regra para a reserva com reembolso parcial depois de concluída, ela entra pelo valor cheio ou pelo valor líquido de reembolso?

**Head:** Boa pergunta, eu nunca tinha pensado nisso separado. Eu diria que pra comissão o que importa é o valor líquido, se teve reembolso parcial, a comissão dela também é menor.

**Eu:** Certo, vou registrar isso como um requisito em aberto, porque hoje o mart de reservas (`fct_bookings`) não desconta reembolso do `total_amount`, ele guarda o valor bruto da reserva. O reembolso mora numa tabela separada de cancelamentos. Pra atender esse requisito eu preciso somar `fct_bookings` com o valor de `refund_amount` de `int_cancellations`, quando existir, e isso não está pronto ainda no D1. Não é um problema grande, mas é trabalho novo, não reaproveita o que já existe direto.

**Head:** Faz sentido, pode entrar como uma fase 2 então, pra não travar a entrega desse mês.

---

## Parte 3 — O conflito de métrica (múltiplas moedas)

**Eu:** Existe um ponto importante para analisarmos. Você pediu "receita total por parceiro". Só que, olhando os dados, os 20 parceiros da base têm reservas em 5 moedas diferentes: BRL, USD, ARS, CLP, COP. Não é "um parceiro, uma moeda", o mesmo parceiro pode ter reservas em mais de uma moeda dependendo de onde o cliente reservou.

**Head:** Ok, mas no fim eu preciso de um número só, tipo "receita da Localiza em outubro foi R$ 850 mil". Não dá só pra converter tudo pra real?

**Eu:** Dá, mas hoje não tem de onde converter com segurança, no banco de dados atual não tenho uma tabela de câmbio, e se eu simplesmente somar `total_amount` de moedas diferentes como se fossem a mesma unidade, o número que sai não quer dizer nada, é como somar reais com dólares e pesos argentinos e chamar o resultado de "reais".

**Head:** Entendi o risco. Mas pro board, eu realmente preciso apresentar um número consolidado, eles não vão querer ver 5 colunas de moeda diferente numa reunião de 20 minutos.

**Eu:** Tenho uma sugestão, para atender inicialmente e mais rapidamente a solicitação. primeiro podemos fazer é:
**reportar aberto por moeda** (o que os dados suportam hoje, sem risco de conversão errada): uma coluna por moeda, sem soma entre elas. Resolve financeiro e pricing, não resolve o "número único" do board e em paralelo e em contato com o time de engenharia de dados, **buscar uma fonte de câmbio oficial e incorporar isso ao pipeline**: o Banco Central do Brasil publica cotação histórica diária, de graça, com API pra BRL/USD/ARS/CLP/COP, cobrindo qualquer período que a gente precise. Com isso, o consolidado em BRL fica correto e defensável, com a taxa do dia da reserva, não uma taxa fixa arbitrária. Porém como envolve outros times, não consigo neste momento definir um prazo para essa melhor alternativa.

**Head:** Certo, vamos fazer a 1 agora, pro relatório detalhado que meu time e o financeiro usam enquanto vocês constroem a 2 como próxima entrega?

**Eu:** Combinado. Vou deixar isso escrito no requisito técnico pra não virar mal-entendido lá na frente.

**Head:** Sim, por favor, deixa isso bem claro em algum lugar que dê pra apontar se alguém questionar.

---

## Parte 4 — Qualidade de dado e confiança

**Eu:** Obervando a qualidade dos dados, preciso te passar 2 pontos que afetam diretamente receita. Primeiro: hoje 297 reservas com status confirmado ou concluído têm o valor da reserva nulo, então elas ficam de fora do cálculo de receita, e mais 156 tinham valor zerado ou negativo, essas também saem. Isso não é bug meu, é dado que já vem assim da origem. Se isso for maior do que uns 2% do total de reservas confirmadas num mês, eu trato como sinal de problema novo na fonte, não mais ruído esperado, e aviso vocês antes de vocês descobrirem batendo o número com o financeiro.

**Head:** Isso já aconteceu comigo antes, um mês o número bateu certinho, no outro simplesmente não batia e ninguém sabia por quê. Ter um aviso automático nisso já ajuda muito.

**Eu:** Segundo: encontrei 10 combinações de usuário e dia com mais de uma reserva no mesmo dia, um caso chegando a 4 reservas no mesmo dia pro mesmo usuário. Pode ser cliente legítimo reservando carro pra família, mas também pode ser padrão de fraude. Hoje isso só fica sinalizado, não é removido da receita automaticamente, porque eu não tenho certeza suficiente pra excluir sozinho.

**Head:** Concordo em não excluir automático, isso é decisão de negócio, não de pipeline. Mas eu quero saber quando isso acontecer com volume relevante, pode virar taxa de comissão paga sobre reserva fraudulenta, que é dinheiro saindo da empresa à toa.

**Eu:** Combinado, vou incluir esse alerta como parte do relatório, não só do pipeline interno.

---

## Parte 5 — Formato, frequência e critério de sucesso

**Eu:** A frequência de atualização você disse mensal, mas antecipando tendência. Mensal realmente resolve ou gostaria de mais algum período de atualização ?

**Head:** Mensal resolve pro relatório de comissão. Mas se der pra eu espiar um número parcial no meio do mês, tipo "como estamos indo até agora", isso ajudaria a não levar susto no fechamento.

**Eu:** Dá pra fazer, colocando o valor do mês corrente como parcial, número fechado só sai depois do mês fechado. e sobre o formato da informação, gostaria de um dashboard, planilha, ou os dois?

**Head:** Dashboard pro board e pro time de pricing acompanhar ao longo do mês. Mas eu ainda preciso conseguir exportar uma versão em planilha pra reunião de comissão com o parceiro, porque eu anoto observação em cima, não posso só mostrar tela.

**Eu:** Anotado, dashboard vivo pra acompanhamento, export em planilha no fechamento do mês pra reunião de comissão. Última pergunta, como eu saberia que entreguei isso com sucesso?

**Head:** Se eu conseguir chegar na reunião de revisão de comissão sem precisar validar manualmente contra a planilha antes, e se o financeiro parar de questionar meu número porque agora tem uma definição só, documentada, que todo mundo usa. E se eu for avisada antes de descobrir sozinha que teve uma queda estranha, tipo o exemplo da TopDrive que você mencionou puxar dado de cancelamento.

**Eu:** Ótimo, isso vira o item de aceite do requisito técnico. Vou formalizar tudo isso em um data contract, pra deixar por escrito o que é receita, o que não é, e o que cada público recebe, assim da próxima vez que alguém perguntar "de onde vem esse número" a resposta está documentada.

---

## Resumo dos pontos levantados

| Tema | Decisão tomada nesta entrevista |
|---|---|
| Definição de receita | `confirmed`/`completed`, fora de cancelamento, igual ao glossário já existente do projeto |
| Reembolso parcial | Fica como fase 2, não bloqueia a entrega do mês 1 |
| Multi-moeda | Fase 1: aberto por moeda (correto, sem risco). Fase 2: tabela de câmbio oficial do BCB |
| Dado nulo/inválido em receita | Reportar volume e alertar se passar de ~2% das reservas confirmadas do mês |
| Reservas suspeitas (mesmo usuário/dia) | Sinalizar no relatório, não excluir automaticamente da receita |
| Frequência | Mensal fechado (oficial) + visão parcial no meio do mês (não oficial) |
| Formato | Dashboard (acompanhamento) + export em planilha (reunião de comissão) |
| Critério de sucesso | Não precisar validar manualmente contra planilha; definição única aceita pelo financeiro; alerta proativo de anomalia |
