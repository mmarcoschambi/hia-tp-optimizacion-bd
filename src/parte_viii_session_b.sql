-- PDF 38-39. MANUAL snippets for separate connection B on isolated hotel_db.
-- Do not source whole file. Use same existing id as session A.
USE hotel_db;
SELECT CONNECTION_ID(), @@version_comment;
SET SESSION lock_wait_timeout = 10;
SET SESSION innodb_lock_wait_timeout = 10;

-- P38 TABLE: while A holds LOCK TABLES reserva READ, this read can proceed.
SELECT id_reserva FROM reserva ORDER BY id_reserva LIMIT 1;
-- Replace 1 with the observed existing id. UPDATE waits on A's READ lock.
-- Run separately; on timeout record error 1205; A must UNLOCK TABLES.
UPDATE reserva SET estado_reserva = estado_reserva WHERE id_reserva = 1;

-- P38 ROW / P39 ROW: after A has started transaction and SELECT FOR UPDATE.
-- Plain consistent read generally proceeds despite A's row lock (InnoDB).
SELECT id_reserva, estado_reserva FROM reserva WHERE id_reserva = 1;
-- Run this in B while A still holds the row lock. B waits or times out;
-- after A ROLLBACK, retry in a NEW autocommit statement to see completion.
UPDATE reserva SET estado_reserva = estado_reserva WHERE id_reserva = 1;
-- Optional alternative: run SELECT ... FOR UPDATE in B while A locks the row;
-- unlike the plain SELECT it waits. Do not execute UPDATE and this together.
SELECT id_reserva FROM reserva WHERE id_reserva = 1 FOR UPDATE;
