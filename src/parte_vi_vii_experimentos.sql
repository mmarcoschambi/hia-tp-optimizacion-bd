-- PDF points 31-37; MySQL 8.0+ / MariaDB with EXPLAIN FORMAT=JSON.
-- Run only on a disposable copy of hotel_db. No timings or plans are asserted here.
-- In mysql CLI use --table --verbose and capture output with --tee=results.log;
-- repeat each SELECT with warmed/cold cache policy recorded separately.
USE hotel_db;
SELECT VERSION(), @@version_comment;
SELECT COUNT(*) AS actual_rows FROM reserva;

-- P31 statistics: compare cardinality estimates before/after refresh on an isolated copy.
SELECT INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME, CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'reserva'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;
SELECT estado_reserva, COUNT(*) AS actual_rows FROM reserva GROUP BY estado_reserva;
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE estado_reserva = 'Finalizada';
ANALYZE TABLE reserva;
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE estado_reserva = 'Finalizada';
-- Record estimated rows, filtered and query_cost before/after; ANALYZE updates shared stats.

-- Optional experimental indexes: first inspect SHOW INDEX FROM reserva; skip equivalent ones.
-- Run CREATE on disposable copy, then ANALYZE TABLE reserva and repeat each baseline.
-- CREATE INDEX idx_pvii_guest_date ON reserva (id_huesped, fecha_inicio);
-- CREATE INDEX idx_pvii_date_guest ON reserva (fecha_inicio, id_huesped);
-- CREATE INDEX idx_pvii_state_date ON reserva (estado_reserva, fecha_inicio);
-- CREATE INDEX idx_pvii_keyset ON reserva (fecha_inicio, id_reserva);
-- DROP INDEX idx_pvii_guest_date ON reserva; -- only if this script created it
-- DROP INDEX idx_pvii_date_guest ON reserva;
-- DROP INDEX idx_pvii_state_date ON reserva;

-- P32 low selectivity may favor ALL; no index selection is guaranteed by SQL.
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE estado_reserva = 'Finalizada';
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE id_huesped = 42;
-- P33 JOIN: compare expression preventing ref access with direct equality.
EXPLAIN FORMAT=JSON SELECT r.id_reserva FROM reserva AS r
JOIN habitacion AS ha ON ha.id_habitacion + 0 = r.id_habitacion
WHERE r.id_huesped = 42;
EXPLAIN FORMAT=JSON SELECT r.id_reserva FROM reserva AS r
JOIN habitacion AS ha ON ha.id_habitacion = r.id_habitacion
WHERE r.id_huesped = 42;

-- P34-37: eight hypotheses; each EXPLAIN must be accompanied by actual SELECT
-- execution on the same snapshot. Capture elapsed time separately for each SELECT.
-- Q1 original
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE YEAR(fecha_inicio) = 2024;
-- Q1 optimized
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE fecha_inicio >= '2024-01-01' AND fecha_inicio < '2025-01-01';

-- Q2 original
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE DATE(fecha_inicio) = '2024-03-01';
-- Q2 optimized
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE fecha_inicio >= '2024-03-01' AND fecha_inicio < '2024-03-02';

-- Q3 original
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE id_huesped + 0 = 42;
-- Q3 optimized
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva WHERE id_huesped = 42;

-- Q4 original (run without idx_pvii_guest_date; save output)
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE id_huesped = 42 AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2025-01-01';
-- Q4 optimized (create idx_pvii_guest_date above, ANALYZE TABLE, run same query)
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE id_huesped = 42 AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2025-01-01';

-- Q5 original (run without idx_pvii_state_date)
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE estado_reserva = 'Cancelada' AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2024-02-01';
-- Q5 optimized (create idx_pvii_state_date, ANALYZE TABLE, run same query)
EXPLAIN FORMAT=JSON SELECT id_reserva FROM reserva
WHERE estado_reserva = 'Cancelada' AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2024-02-01';

-- Q6 original: an expression on JOIN key can inhibit indexed lookup.
EXPLAIN FORMAT=JSON SELECT r.id_reserva FROM reserva AS r
JOIN habitacion AS ha ON ha.id_habitacion + 0 = r.id_habitacion
WHERE r.id_huesped = 42;
-- Q6 optimized
EXPLAIN FORMAT=JSON SELECT r.id_reserva FROM reserva AS r
JOIN habitacion AS ha ON ha.id_habitacion = r.id_habitacion
WHERE r.id_huesped = 42;

-- Q7 original: transport all columns (not the same projection as optimized).
EXPLAIN FORMAT=JSON SELECT * FROM reserva WHERE id_huesped = 42;
-- Q7 optimized: narrow projection; compare byte count as well as latency.
EXPLAIN FORMAT=JSON SELECT id_reserva, fecha_inicio FROM reserva WHERE id_huesped = 42;

-- Q8 original: offset skips earlier rows; record cursor at position 1000
-- using SELECT fecha_inicio,id_reserva ... LIMIT 999,1 on the same snapshot.
EXPLAIN FORMAT=JSON SELECT id_reserva, fecha_inicio FROM reserva
ORDER BY fecha_inicio, id_reserva LIMIT 20 OFFSET 1000;
-- Q8 optimized: replace literal cursor with the observed 1000th row; the
-- example literals are placeholders, NOT a measured equivalent page.
EXPLAIN FORMAT=JSON SELECT id_reserva, fecha_inicio FROM reserva
WHERE fecha_inicio > '2024-01-01'
   OR (fecha_inicio = '2024-01-01' AND id_reserva > 1000)
ORDER BY fecha_inicio, id_reserva LIMIT 20;
-- Index candidate for Q8: idx_pvii_keyset (fecha_inicio,id_reserva).
-- MariaDB 10.6 chose index scan for the tuple comparison; explicit OR enabled range.
