-- ============================================================
-- PARTE X: Escalabilidad y Estructuras Avanzadas (Puntos 50, 51 y 52)
-- Base objetivo: hotel_db / MySQL-MariaDB (InnoDB)
-- ============================================================

USE hotel_db;

-- ------------------------------------------------------------
-- Punto 50: Estrategia de Particionamiento por Rango de Fechas
-- ------------------------------------------------------------
-- Dividimos la tabla masiva de reservas por año para optimizar accesos físicos.

ALTER TABLE reserva PARTITION BY RANGE (YEAR(fecha_inicio)) (
    PARTITION p_historico VALUES LESS THAN (2023),
    PARTITION p_2023 VALUES LESS THAN (2024),
    PARTITION p_2024 VALUES LESS THAN (2025),
    PARTITION p_2025 VALUES LESS THAN (2026),
    PARTITION p_futuro VALUES LESS THAN MAXVALUE
);

-- ------------------------------------------------------------
-- Punto 51: Demostración de Partition Pruning (Poda de Particiones)
-- ------------------------------------------------------------
-- El optimizador solo escaneará la partición 'p_2023', ignorando los demás millones de filas.

EXPLAIN PARTITIONS
SELECT id_reserva, id_huesped, fecha_inicio, estado_reserva
FROM reserva
WHERE fecha_inicio >= '2023-06-01' AND fecha_inicio <= '2023-12-31';

-- ------------------------------------------------------------
-- Punto 52: Simulación de Vista Materializada (Tabla Resumen Precalculada)
-- ------------------------------------------------------------
-- Como MySQL no tiene 'CREATE MATERIALIZED VIEW', creamos una tabla de resumen.

CREATE TABLE IF NOT EXISTS vista_mat_resumen_mensual_hotel (
    id_hotel INT,
    nombre_hotel VARCHAR(100),
    anio INT,
    mes INT,
    total_reservas INT,
    ingreso_total DECIMAL(12,2),
    PRIMARY KEY (id_hotel, anio, mes)
);

-- Proceso Batch/Refresco para consolidar los 6M de filas en una tablaLiviana
REPLACE INTO vista_mat_resumen_mensual_hotel
SELECT 
    ho.id_hotel,
    ho.nombre_hotel,
    YEAR(r.fecha_inicio) AS anio,
    MONTH(r.fecha_inicio) AS mes,
    COUNT(*) AS total_reservas,
    SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche) AS ingreso_total
FROM reserva AS r
INNER JOIN habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN hotel AS ho ON ho.id_hotel = ha.id_hotel
INNER JOIN tipo_habitacion AS th ON th.id_tipo_habitacion = ha.id_tipo_habitacion
WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
GROUP BY ho.id_hotel, ho.nombre_hotel, YEAR(r.fecha_inicio), MONTH(r.fecha_inicio);

-- Consulta ultrarrápida (milisegundos) sobre la vista materializada
SELECT * 
FROM vista_mat_resumen_mensual_hotel
WHERE anio = 2023
ORDER BY ingreso_total DESC;