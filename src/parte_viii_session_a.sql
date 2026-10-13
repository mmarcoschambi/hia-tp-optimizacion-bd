-- PDF 38-39. MANUAL snippets for session A on an ISOLATED hotel_db copy.
-- Do not source the whole file: coordinate phases with session B per docs.
USE hotel_db;
SELECT CONNECTION_ID(), @@version_comment;
SELECT id_reserva, estado_reserva FROM reserva ORDER BY id_reserva LIMIT 1;
-- Write down the returned id and give the same numeric id to session B.

-- P38 TABLE: phase 1. A obtains a shared table READ lock; pause before unlock.
LOCK TABLES reserva READ;
SELECT id_reserva FROM reserva ORDER BY id_reserva LIMIT 1;
-- Tell B to run its P38 TABLE statements. Once B has observed a wait:
UNLOCK TABLES;

-- P38 ROW / P39 ROW: phase 2. Only start once table phase has finished.
-- Replace 1 with the observed id_reserva in BOTH sessions. Abort if id 1 absent.
START TRANSACTION;
SELECT id_reserva, estado_reserva FROM reserva WHERE id_reserva = 1 FOR UPDATE;
-- A holds an exclusive row lock. Tell B to run non-locking SELECT then UPDATE.
-- After observing B wait (or timeout), release without changing any data:
ROLLBACK;
-- Never leave A idle with an open transaction or table lock.
