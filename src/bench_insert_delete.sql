-- ============================================================================
-- bench_insert_delete.sql — Costo de escritura según cantidad de índices
-- ============================================================================
-- OBJETIVO: demostrar que cada índice secundario encarece INSERT/DELETE
-- (cada escritura mantiene un B-Tree O(log n) adicional por índice).
--
-- SEGURIDAD: trabaja SOLO sobre la tabla de PRUEBA `bench_reserva_like`,
-- creada y destruida por este script. NUNCA toca `Reserva` ni ninguna
-- tabla del laboratorio.
--
-- CÓMO CORRER (pegar salida en el informe):
--   mysql -u root -p hotel_db < bench_insert_delete.sql
--
-- TIEMPOS: no se afirma ningún valor en este archivo; el propio script
-- imprime los microsegundos medidos. Fuera del script figura [MEDIR].
-- ============================================================================

USE hotel_db;

-- Limpieza previa idempotente (por si una corrida anterior quedó a medias).
DROP TABLE IF EXISTS bench_reserva_like;

-- ------------------------------------------------------------------
-- ESCENARIO A: pocos índices (solo PK). Base de comparación.
-- ------------------------------------------------------------------
CREATE TABLE bench_reserva_like (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_habitacion INT NOT NULL,
    id_huesped INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'Confirmada'
) ENGINE = InnoDB;

-- Medición A1: INSERT de 1000 filas (lote único con filas generadas).
SET @t0 = NOW(6);
INSERT INTO bench_reserva_like (id_habitacion, id_huesped, fecha_inicio, fecha_fin, estado)
SELECT 1 + (t.n % 5000), 1 + (t.n % 500000),
       DATE('2023-01-01') + INTERVAL (t.n % 1000) DAY,
       DATE('2023-01-01') + INTERVAL (t.n % 1000) + 3 DAY,
       ELT(1 + (t.n % 3), 'Confirmada', 'Finalizada', 'Cancelada')
FROM (
    SELECT @rownum := @rownum + 1 AS n
    FROM (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1,
         (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2,
         (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3,
         (SELECT @rownum := 0) init
    LIMIT 1000
) AS t;
SET @t1 = NOW(6);
SELECT 'A1_INSERT_1000_POCOS_INDICES_us' AS prueba,
       TIMESTAMPDIFF(MICROSECOND, @t0, @t1) AS microsegundos;

-- Medición A2: DELETE de esas 1000 filas.
SET @t0 = NOW(6);
DELETE FROM bench_reserva_like;
SET @t1 = NOW(6);
SELECT 'A2_DELETE_1000_POCOS_INDICES_us' AS prueba,
       TIMESTAMPDIFF(MICROSECOND, @t0, @t1) AS microsegundos;

-- ------------------------------------------------------------------
-- ESCENARIO B: muchos índices (PK + 4 secundarios). Misma carga.
-- ------------------------------------------------------------------
CREATE INDEX idx_bench_huesped ON bench_reserva_like (id_huesped);
CREATE INDEX idx_bench_habitacion ON bench_reserva_like (id_habitacion);
CREATE INDEX idx_bench_fecha_estado ON bench_reserva_like (fecha_inicio, estado);
CREATE INDEX idx_bench_keyset ON bench_reserva_like (fecha_inicio, id);

-- Medición B1: INSERT de 1000 filas (idéntico lote que en A1).
SET @t0 = NOW(6);
INSERT INTO bench_reserva_like (id_habitacion, id_huesped, fecha_inicio, fecha_fin, estado)
SELECT 1 + (t.n % 5000), 1 + (t.n % 500000),
       DATE('2023-01-01') + INTERVAL (t.n % 1000) DAY,
       DATE('2023-01-01') + INTERVAL (t.n % 1000) + 3 DAY,
       ELT(1 + (t.n % 3), 'Confirmada', 'Finalizada', 'Cancelada')
FROM (
    SELECT @rownum := @rownum + 1 AS n
    FROM (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1,
         (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2,
         (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3,
         (SELECT @rownum := 0) init
    LIMIT 1000
) AS t;
SET @t1 = NOW(6);
SELECT 'B1_INSERT_1000_MUCHOS_INDICES_us' AS prueba,
       TIMESTAMPDIFF(MICROSECOND, @t0, @t1) AS microsegundos;

-- Medición B2: DELETE de esas 1000 filas.
SET @t0 = NOW(6);
DELETE FROM bench_reserva_like;
SET @t1 = NOW(6);
SELECT 'B2_DELETE_1000_MUCHOS_INDICES_us' AS prueba,
       TIMESTAMPDIFF(MICROSECOND, @t0, @t1) AS microsegundos;

-- Índices activos durante el escenario B (evidencia para el informe).
SHOW INDEX FROM bench_reserva_like;

-- ------------------------------------------------------------------
-- CLEANUP (descomentar para borrar la tabla de prueba al finalizar):
-- DROP TABLE IF EXISTS bench_reserva_like;
-- ------------------------------------------------------------------
