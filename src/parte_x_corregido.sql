-- ============================================================
-- PARTE X CORREGIDO — hotel_db / MariaDB 10.6.23 / InnoDB
-- Tabla real: Reserva(id_reserva AI PK, id_habitacion FK,
--   id_huesped FK, fecha_inicio DATE, fecha_fin DATE,
--   estado_reserva). Reserva ~6M filas; Habitacion/Hotel
--   vacias; NO existe tipo_habitacion.
-- REGLA DE ORO: nunca tocar la Reserva real sin avisar.
-- Todo tiempo es [MEDIR]: cero numeros inventados.
--
-- ESTADO ACTUAL: ya ejecutado contra la base real. Los numeros medidos,
-- el procedimiento que funciona y los intentos que fallaron estan en:
--   docs/parte_x_particionamiento_resultados.md
-- Corregido al ejecutarlo de verdad:
--   1) Las FK impiden particionar -> el error real es 1217, no 1503.
--   2) El EXPLAIN comun NO trae columna "partitions" en 10.6.23:
--      la que la expone es EXPLAIN PARTITIONS.
--   3) El ALTER monolítico NO completa con 6M filas y buffer pool de 128 MiB.
--      Lo que si funciona: buffer pool en runtime + destino sin indices
--      secundarios + carga por lotes + indices en bloque + RENAME de swap.
-- ============================================================

USE hotel_db;

-- ============================================================
-- SEC 0 — RECONOCIMIENTO (solo lectura, CORRE ESTO PRIMERO)
-- Si hay FK o PK distinta a la esperada, NO SIGAS:
-- frena y adapta los ALTER de la Sec 2 al DDL real.
-- ============================================================

SELECT VERSION();
SELECT @@innodb_buffer_pool_size AS buffer_pool_bytes;
SELECT @@innodb_buffer_pool_size / 1024 / 1024 AS buffer_pool_mib;
SHOW CREATE TABLE Reserva;
SHOW INDEX FROM Reserva;
SELECT TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'hotel_db'
  AND TABLE_NAME = 'Reserva';

-- ============================================================
-- SEC 1 — MEDICION ANTES (tabla sin particionar)
-- Rango 2023 SARGable: >= con < (limite superior exclusivo).
-- Mirar en EXPLAIN PARTITIONS: type / key / rows / Extra / partitions.
-- partitions = NULL/vacio = tabla no particionada (esperado).
-- ============================================================

-- 1a) Conteo del rango (una sola fila, barato de transferir)
ANALYZE SELECT COUNT(*) AS total_2023
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01';
-- [MEDIR] tiempo r_total_time_ms + type/key/rows/Extra/partitions.

-- 1b) Muestra del mismo rango (mismo filtro, para EXPLAIN)
ANALYZE SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01'
LIMIT 100;
-- [MEDIR] tiempo real antes.

EXPLAIN PARTITIONS SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01'
LIMIT 100;
-- [MEDIR] copiar type, key, rows, Extra, partitions (antes).

-- ============================================================
-- SEC 2 — PARTICIONAMIENTO (PELIGROSO: LEER ANTES DE EJECUTAR)
-- 1) InnoDB NO permite particionar una tabla con FK.
--    MEDIDO en MariaDB 10.6.23: falla con
--    ERROR 1217 (23000) "Cannot delete or update a parent row:
--    a foreign key constraint fails" (no es 1503).
--    Hay que eliminar primero las FK de Reserva. Verificado tambien en una
--    tabla descartable: la misma tabla SIN FK si se particiona.
-- 2) La PK debe incluir la columna de particion:
--    PK compuesta (id_reserva, fecha_inicio).
-- 3) MEDIDO: el ALTER monolítico NO COMPLETA con 6M filas y buffer pool de
--    128 MiB. Se estanca en "copy to tmp table" con ~2,9M row locks y
--    0 writes/s. Tampoco sirve ALGORITHM=COPY. La migracion por lotes con
--    el buffer pool elevado en runtime si completa (150 s).
-- 4) RANGE COLUMNS(fecha_inicio) es la via recomendada: compara la columna
--    DATE directamente, sin funcion de particion, y poda igual (medido:
--    EXPLAIN PARTITIONS devuelve p_2023). YEAR() no hace falta.
-- Todo lo de abajo va COMENTADO por defecto a proposito.
-- ============================================================

-- -- 2a) Descubrir nombres reales de FK (ver salida Sec 0) y borrarlas:
-- -- ALTER TABLE Reserva DROP FOREIGN KEY fk_reserva_habitacion;
-- -- ALTER TABLE Reserva DROP FOREIGN KEY fk_reserva_huesped;
-- -- (Reemplazar fk_... por los nombres reales de SHOW CREATE TABLE Reserva.)

-- -- 2b) Cambiar PK simple por compuesta (incluye fecha_inicio):
-- -- ALTER TABLE Reserva DROP PRIMARY KEY, ADD PRIMARY KEY (id_reserva, fecha_inicio);

-- -- 2c) Particionar por rango de fecha (5 particiones):
-- -- ALTER TABLE Reserva PARTITION BY RANGE (TO_DAYS(fecha_inicio)) (
-- --     PARTITION p_historico VALUES LESS THAN (TO_DAYS('2023-01-01')),
-- --     PARTITION p_2023     VALUES LESS THAN (TO_DAYS('2024-01-01')),
-- --     PARTITION p_2024     VALUES LESS THAN (TO_DAYS('2025-01-01')),
-- --     PARTITION p_2025     VALUES LESS THAN (TO_DAYS('2026-01-01')),
-- --     PARTITION p_futuro   VALUES LESS THAN MAXVALUE
-- -- );

-- -- 2d) ALTERNATIVA RECOMENDADA: no tocar la tabla real,
-- --     particionar una COPIA y medir ahi:
-- -- CREATE TABLE IF NOT EXISTS Reserva_part LIKE Reserva;
-- -- ALTER TABLE Reserva_part DROP FOREIGN KEY fk_reserva_habitacion;
-- -- ALTER TABLE Reserva_part DROP FOREIGN KEY fk_reserva_huesped;
-- -- ALTER TABLE Reserva_part DROP PRIMARY KEY, ADD PRIMARY KEY (id_reserva, fecha_inicio);
-- -- ALTER TABLE Reserva_part PARTITION BY RANGE (TO_DAYS(fecha_inicio)) (
-- --     PARTITION p_historico VALUES LESS THAN (TO_DAYS('2023-01-01')),
-- --     PARTITION p_2023     VALUES LESS THAN (TO_DAYS('2024-01-01')),
-- --     PARTITION p_2024     VALUES LESS THAN (TO_DAYS('2025-01-01')),
-- --     PARTITION p_2025     VALUES LESS THAN (TO_DAYS('2026-01-01')),
-- --     PARTITION p_futuro   VALUES LESS THAN MAXVALUE
-- -- );
-- -- INSERT INTO Reserva_part SELECT * FROM Reserva;  -- tarda varios minutos con 6M
-- -- (Repetir Sec 1 y Sec 3 contra Reserva_part para comparar.)

-- ============================================================
-- SEC 3 — MEDICION DESPUES + PRUNING (solo si se particiono)
-- Misma consulta de Sec 1. En EXPLAIN PARTITIONS mirar la columna
-- partitions: debe decir p_2023 (una sola particion). MEDIDO: si.
-- Comparar [MEDIR] antes vs despues; no se afirma % fijo.
-- ============================================================

ANALYZE SELECT COUNT(*) AS total_2023
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01';
-- [MEDIR] tiempo despues.

ANALYZE SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01'
LIMIT 100;
-- [MEDIR] tiempo despues.

EXPLAIN PARTITIONS SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01'
LIMIT 100;
-- [MEDIR] copiar type, key, rows, Extra, partitions (= p_2023 esperado).

-- Si se uso la copia: repetir el EXPLAIN contra Reserva_part
-- y comparar partitions/type/rows/tiempo con Sec 1.
-- EXPLAIN SELECT id_reserva, fecha_inicio FROM Reserva_part
-- WHERE fecha_inicio >= '2023-06-01' AND fecha_inicio < '2024-01-01' LIMIT 100;

-- ============================================================
-- SEC 4 — RESUMEN MENSUAL SOLO-RESERVA
-- Solo sobre Reserva porque Habitacion/Hotel estan vacias
-- (cualquier JOIN devolveria 0 filas) y tipo_habitacion
-- NO existe en este laboratorio.
-- MariaDB no tiene CREATE MATERIALIZED VIEW: tabla resumen
-- + vista que la expone. Refresco con REPLACE INTO (batch).
-- ============================================================

CREATE TABLE IF NOT EXISTS vista_mat_resumen_mensual (
    anio INT NOT NULL,
    mes INT NOT NULL,
    total_reservas INT NOT NULL,
    noches_totales BIGINT NOT NULL,
    PRIMARY KEY (anio, mes)
);

REPLACE INTO vista_mat_resumen_mensual (anio, mes, total_reservas, noches_totales)
SELECT YEAR(fecha_inicio) AS anio,
       MONTH(fecha_inicio) AS mes,
       COUNT(*) AS total_reservas,
       SUM(DATEDIFF(fecha_fin, fecha_inicio)) AS noches_totales
FROM Reserva
WHERE estado_reserva IN ('Confirmada', 'Finalizada')
GROUP BY YEAR(fecha_inicio), MONTH(fecha_inicio);

CREATE OR REPLACE VIEW v_resumen_mensual AS
SELECT * FROM vista_mat_resumen_mensual;

-- Consulta ultrarrapida: lee ~36 filas (meses), no 6M
ANALYZE SELECT * FROM vista_mat_resumen_mensual
WHERE anio = 2023
ORDER BY mes;
-- [MEDIR] tiempo tabla resumen vs. agregacion directa sobre Reserva.

-- Agregacion directa equivalente (para comparar, cara: lee 6M):
-- ANALYZE SELECT YEAR(fecha_inicio) AS anio, MONTH(fecha_inicio) AS mes,
--        COUNT(*) AS total_reservas,
--        SUM(DATEDIFF(fecha_fin, fecha_inicio)) AS noches_totales
-- FROM Reserva
-- WHERE estado_reserva IN ('Confirmada', 'Finalizada')
--   AND fecha_inicio >= '2023-01-01' AND fecha_inicio < '2024-01-01'
-- GROUP BY YEAR(fecha_inicio), MONTH(fecha_inicio);
-- [MEDIR] copiar tiempo y comparar con la consulta a la tabla resumen.

-- ============================================================
-- SEC 5 — SLOW LOG (Punto 47) + NOTA POOL (Punto 46)
-- Punto 46 (pool): va en bench_pool.py ya existente, no aqui:
--   python bench_pool.py  (3 modos: conexion por consulta,
--   conexion reutilizada, pool size=5). [MEDIR] pegar tabla.
-- ============================================================

-- Slow log: activar y capturar una consulta lenta real
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
-- SET GLOBAL log_queries_not_using_indexes = ON;  -- SOLO si el usuario tiene SUPER; si da error de privilegios, omitir.

-- Generar una consulta capturable (escaneo pesado a proposito):
SELECT COUNT(*), SUM(DATEDIFF(fecha_fin, fecha_inicio))
FROM Reserva
WHERE estado_reserva = 'Finalizada';
-- [MEDIR] tiempo de esta consulta.

-- Leer lo capturado (motor CSV por defecto en MariaDB):
SELECT start_time, query_time, rows_examined, sql_text
FROM mysql.slow_log
ORDER BY start_time DESC
LIMIT 10;
-- [MEDIR] pegar filas capturadas. Si slow_log esta vacia: revisar
-- SHOW VARIABLES LIKE 'slow_query_log%'; y long_query_time.
