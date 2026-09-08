
Pontos observados em testes em staging
Construída o arquivo de cada raw somente com as padronizações básicas de cada campo
duplicatas encontradas em staging: partners=2, searches=236, sessions=342, cancellations=79, bookings=118

__________________________

Regras aplicadas em models/intermediate

int_sessions_deduped.sql
exclui is_bot = true e, entre duplicatas de session_id, mantém a mais recente (started_at desc).

int_bookings_valid.sql
parceiro active
deduplicação mantendo a reserva mais recente por booking_id
somente leitura dos total_amount > 0 obrigatório para confirmed/completed ou sem status confirmed/completed para casos zerados.

int_cancellations_valid.sql
retira as duplicadas por cancellation_id, mantendo o mais rescente por cancelled_at somente os que estão validos no stg_bookings.
---refund_amount não deve ser superior ao total_amount da reserva associada

__________________

Regras aplicadas na camada marts
dim_partners.sql, duplicatas, mantém o registro com updated_at mais recente (ou created_at se updated_at for nulo)
dim_users.sql, usuários autenticados identificados em sessões e reservas, anônimos sem user_id, ficam de fora.
