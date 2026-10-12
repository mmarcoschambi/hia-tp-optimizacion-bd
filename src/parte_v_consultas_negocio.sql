-- Parte V - Consultas complejas de negocio (Puntos 24 al 30)
-- Base objetivo: hotel_db / MySQL-MariaDB.
--
-- Supuestos de esquema usados por el TP:
--   reserva(id_reserva, id_habitacion, id_huesped, fecha_inicio, fecha_fin, estado_reserva)
--   huesped(id_huesped, nombre, apellido, email)
--   habitacion(id_habitacion, id_hotel, id_tipo_habitacion, numero_habitacion)
--   tipo_habitacion(id_tipo_habitacion, nombre_tipo, precio_noche)
--   hotel(id_hotel, nombre_hotel, ciudad)
--
-- En la carga masiva existente se verifican las columnas principales de reserva.
-- Las tablas relacionadas responden al modelo normalizado esperado por el dominio hotelero.
-- Si una instalación usa nombres distintos, conservar la forma lógica y ajustar aliases/columnas.

USE hotel_db;

/*
Índices recomendados para evitar escaneos completos innecesarios sobre 6M reservas.
Ejecutarlos solo si no existen índices equivalentes.

CREATE INDEX idx_reserva_fecha_estado_habitacion
    ON reserva (fecha_inicio, estado_reserva, id_habitacion);

CREATE INDEX idx_reserva_huesped_fecha_estado
    ON reserva (id_huesped, fecha_inicio, estado_reserva);

CREATE INDEX idx_reserva_habitacion_rango_estado
    ON reserva (id_habitacion, fecha_inicio, fecha_fin, estado_reserva);

CREATE INDEX idx_reserva_keyset
    ON reserva (fecha_inicio, id_reserva);

CREATE INDEX idx_habitacion_hotel_tipo
    ON habitacion (id_hotel, id_tipo_habitacion, id_habitacion);
*/

-- ============================================================
-- P24: Reservas por rango de fechas y estado con conteo y montos
-- ============================================================
-- Objetivo: resumir volumen y facturación estimada para un rango acotado.
-- Optimización: el filtro por fecha + estado aprovecha idx_reserva_fecha_estado_habitacion;
-- el monto se deriva por noches * precio_noche para no depender de una columna denormalizada.
SET @p24_fecha_desde = DATE('2023-06-01');
SET @p24_fecha_hasta = DATE('2023-12-31');
SET @p24_estado = 'Finalizada';

SELECT
    r.estado_reserva,
    COUNT(*) AS total_reservas,
    SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales,
    SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche) AS monto_estimado_total,
    AVG(DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche) AS ticket_promedio_estimado
FROM reserva AS r
INNER JOIN habitacion AS ha
    ON ha.id_habitacion = r.id_habitacion
INNER JOIN tipo_habitacion AS th
    ON th.id_tipo_habitacion = ha.id_tipo_habitacion
WHERE r.fecha_inicio >= @p24_fecha_desde
  AND r.fecha_inicio < DATE_ADD(@p24_fecha_hasta, INTERVAL 1 DAY)
  AND r.estado_reserva = @p24_estado
GROUP BY r.estado_reserva;

-- ============================================================
-- P25: Relación con huéspedes e historial usando INNER JOIN y LEFT JOIN
-- ============================================================
-- Objetivo: listar reservas del período con datos del huésped y su historial previo.
-- Optimización: primero se recorta la reserva actual por fecha; el historial se agrega por huésped.
SET @p25_fecha_desde = DATE('2023-06-01');
SET @p25_fecha_hasta = DATE('2023-12-31');

WITH historial_huesped AS (
    SELECT
        r_hist.id_huesped,
        COUNT(*) AS reservas_historicas,
        SUM(r_hist.estado_reserva = 'Cancelada') AS cancelaciones_historicas,
        MAX(r_hist.fecha_fin) AS ultima_estadia
    FROM reserva AS r_hist
    WHERE r_hist.fecha_inicio < @p25_fecha_desde
    GROUP BY r_hist.id_huesped
)
SELECT
    r.id_reserva,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado_reserva,
    h.id_huesped,
    h.nombre,
    h.apellido,
    h.email,
    COALESCE(hist.reservas_historicas, 0) AS reservas_historicas,
    COALESCE(hist.cancelaciones_historicas, 0) AS cancelaciones_historicas,
    hist.ultima_estadia
FROM reserva AS r
INNER JOIN huesped AS h
    ON h.id_huesped = r.id_huesped
LEFT JOIN historial_huesped AS hist
    ON hist.id_huesped = r.id_huesped
WHERE r.fecha_inicio >= @p25_fecha_desde
  AND r.fecha_inicio < DATE_ADD(@p25_fecha_hasta, INTERVAL 1 DAY)
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;

-- ============================================================
-- P26: Análisis de ocupación por hotel y tipo de habitación
-- ============================================================
-- Objetivo: medir ocupación confirmada/finalizada por hotel y tipo de habitación.
-- Optimización: se usa condición de solapamiento de rangos para no perder reservas que
-- empiezan antes del período pero ocupan noches dentro del período analizado.
SET @p26_fecha_desde = DATE('2023-07-01');
SET @p26_fecha_hasta = DATE('2023-07-31');

WITH parametros AS (
    SELECT
        @p26_fecha_desde AS fecha_desde,
        DATE_ADD(@p26_fecha_hasta, INTERVAL 1 DAY) AS fecha_hasta_exclusiva,
        DATEDIFF(DATE_ADD(@p26_fecha_hasta, INTERVAL 1 DAY), @p26_fecha_desde) AS dias_periodo
), habitaciones_base AS (
    SELECT
        ho.id_hotel,
        ho.nombre_hotel,
        th.id_tipo_habitacion,
        th.nombre_tipo,
        COUNT(*) AS habitaciones_disponibles
    FROM habitacion AS ha
    INNER JOIN hotel AS ho
        ON ho.id_hotel = ha.id_hotel
    INNER JOIN tipo_habitacion AS th
        ON th.id_tipo_habitacion = ha.id_tipo_habitacion
    GROUP BY ho.id_hotel, ho.nombre_hotel, th.id_tipo_habitacion, th.nombre_tipo
), noches_ocupadas AS (
    SELECT
        ho.id_hotel,
        th.id_tipo_habitacion,
        SUM(
            DATEDIFF(
                LEAST(r.fecha_fin, p.fecha_hasta_exclusiva),
                GREATEST(r.fecha_inicio, p.fecha_desde)
            )
        ) AS noches_ocupadas
    FROM reserva AS r
    INNER JOIN habitacion AS ha
        ON ha.id_habitacion = r.id_habitacion
    INNER JOIN hotel AS ho
        ON ho.id_hotel = ha.id_hotel
    INNER JOIN tipo_habitacion AS th
        ON th.id_tipo_habitacion = ha.id_tipo_habitacion
    CROSS JOIN parametros AS p
    WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
      AND r.fecha_inicio < p.fecha_hasta_exclusiva
      AND r.fecha_fin > p.fecha_desde
    GROUP BY ho.id_hotel, th.id_tipo_habitacion
)
SELECT
    hb.nombre_hotel,
    hb.nombre_tipo,
    hb.habitaciones_disponibles,
    COALESCE(no.noches_ocupadas, 0) AS noches_ocupadas,
    hb.habitaciones_disponibles * p.dias_periodo AS noches_disponibles,
    ROUND(
        COALESCE(no.noches_ocupadas, 0)
        / NULLIF(hb.habitaciones_disponibles * p.dias_periodo, 0) * 100,
        2
    ) AS porcentaje_ocupacion
FROM habitaciones_base AS hb
CROSS JOIN parametros AS p
LEFT JOIN noches_ocupadas AS no
    ON no.id_hotel = hb.id_hotel
   AND no.id_tipo_habitacion = hb.id_tipo_habitacion
ORDER BY porcentaje_ocupacion DESC, hb.nombre_hotel, hb.nombre_tipo;

-- ============================================================
-- P27: Detección de patrones de cancelación con subconsultas / EXISTS
-- ============================================================
-- Objetivo: detectar huéspedes con cancelaciones repetidas y actividad confirmada posterior.
-- Optimización: la subconsulta correlacionada usa idx_reserva_huesped_fecha_estado.
SET @p27_fecha_desde = DATE('2023-01-01');
SET @p27_min_cancelaciones = 3;

SELECT
    h.id_huesped,
    h.nombre,
    h.apellido,
    COUNT(*) AS cancelaciones_periodo,
    MIN(r.fecha_inicio) AS primera_cancelacion,
    MAX(r.fecha_inicio) AS ultima_cancelacion
FROM huesped AS h
INNER JOIN reserva AS r
    ON r.id_huesped = h.id_huesped
WHERE r.estado_reserva = 'Cancelada'
  AND r.fecha_inicio >= @p27_fecha_desde
  AND EXISTS (
      SELECT 1
      FROM reserva AS r_ok
      WHERE r_ok.id_huesped = h.id_huesped
        AND r_ok.estado_reserva IN ('Confirmada', 'Finalizada')
        AND r_ok.fecha_inicio > r.fecha_inicio
  )
GROUP BY h.id_huesped, h.nombre, h.apellido
HAVING COUNT(*) >= @p27_min_cancelaciones
ORDER BY cancelaciones_periodo DESC, ultima_cancelacion DESC;

-- ============================================================
-- P28: Segmentación de clientes con CASE WHEN
-- ============================================================
-- Objetivo: clasificar huéspedes por valor, frecuencia y riesgo de cancelación.
-- Optimización: se agrega una vez por huésped y se clasifica sobre métricas derivadas.
SET @p28_fecha_desde = DATE('2023-01-01');
SET @p28_fecha_hasta = DATE('2025-12-31');

WITH metricas_cliente AS (
    SELECT
        h.id_huesped,
        h.nombre,
        h.apellido,
        COUNT(r.id_reserva) AS total_reservas,
        SUM(r.estado_reserva = 'Cancelada') AS total_cancelaciones,
        SUM(r.estado_reserva IN ('Confirmada', 'Finalizada')) AS reservas_no_canceladas,
        SUM(
            CASE
                WHEN r.estado_reserva IN ('Confirmada', 'Finalizada')
                THEN DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche
                ELSE 0
            END
        ) AS monto_estimado_cliente
    FROM huesped AS h
    LEFT JOIN reserva AS r
        ON r.id_huesped = h.id_huesped
       AND r.fecha_inicio >= @p28_fecha_desde
       AND r.fecha_inicio < DATE_ADD(@p28_fecha_hasta, INTERVAL 1 DAY)
    LEFT JOIN habitacion AS ha
        ON ha.id_habitacion = r.id_habitacion
    LEFT JOIN tipo_habitacion AS th
        ON th.id_tipo_habitacion = ha.id_tipo_habitacion
    GROUP BY h.id_huesped, h.nombre, h.apellido
)
SELECT
    id_huesped,
    nombre,
    apellido,
    total_reservas,
    total_cancelaciones,
    monto_estimado_cliente,
    CASE
        WHEN total_reservas = 0 THEN 'Sin actividad'
        WHEN total_cancelaciones / NULLIF(total_reservas, 0) >= 0.50 THEN 'Riesgo alto de cancelacion'
        WHEN monto_estimado_cliente >= 100000 OR reservas_no_canceladas >= 10 THEN 'Cliente premium'
        WHEN reservas_no_canceladas BETWEEN 3 AND 9 THEN 'Cliente frecuente'
        ELSE 'Cliente ocasional'
    END AS segmento_cliente
FROM metricas_cliente
ORDER BY monto_estimado_cliente DESC, total_reservas DESC;

-- ============================================================
-- P29: Agregaciones avanzadas con GROUP BY, HAVING y ordenamiento por rendimiento
-- ============================================================
-- Objetivo: encontrar combinaciones hotel/tipo rentables y con volumen suficiente.
-- Optimización: HAVING descarta grupos con poco soporte estadístico y el ORDER BY prioriza KPIs.
SET @p29_fecha_desde = DATE('2023-01-01');
SET @p29_fecha_hasta = DATE('2025-12-31');
SET @p29_min_reservas = 1000;

SELECT
    ho.id_hotel,
    ho.nombre_hotel,
    th.id_tipo_habitacion,
    th.nombre_tipo,
    COUNT(*) AS total_reservas,
    SUM(r.estado_reserva = 'Cancelada') AS reservas_canceladas,
    ROUND(SUM(r.estado_reserva = 'Cancelada') / COUNT(*) * 100, 2) AS tasa_cancelacion_pct,
    SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales,
    SUM(
        CASE
            WHEN r.estado_reserva IN ('Confirmada', 'Finalizada')
            THEN DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche
            ELSE 0
        END
    ) AS ingreso_estimado,
    ROUND(
        SUM(
            CASE
                WHEN r.estado_reserva IN ('Confirmada', 'Finalizada')
                THEN DATEDIFF(r.fecha_fin, r.fecha_inicio) * th.precio_noche
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS ingreso_promedio_por_reserva
FROM reserva AS r
INNER JOIN habitacion AS ha
    ON ha.id_habitacion = r.id_habitacion
INNER JOIN hotel AS ho
    ON ho.id_hotel = ha.id_hotel
INNER JOIN tipo_habitacion AS th
    ON th.id_tipo_habitacion = ha.id_tipo_habitacion
WHERE r.fecha_inicio >= @p29_fecha_desde
  AND r.fecha_inicio < DATE_ADD(@p29_fecha_hasta, INTERVAL 1 DAY)
GROUP BY ho.id_hotel, ho.nombre_hotel, th.id_tipo_habitacion, th.nombre_tipo
HAVING COUNT(*) >= @p29_min_reservas
   AND tasa_cancelacion_pct < 35
ORDER BY ingreso_estimado DESC, ingreso_promedio_por_reserva DESC, total_reservas DESC;

-- ============================================================
-- P30: Keyset pagination eficiente sobre grandes volúmenes
-- ============================================================
-- Objetivo: paginar reservas sin OFFSET alto. OFFSET N obliga al motor a leer y descartar
-- N filas; keyset usa la última clave vista para continuar con búsqueda indexada.
SET @p30_page_size = 100;

-- Primera página: usa el índice (fecha_inicio, id_reserva) para ordenar y limitar.
SELECT
    r.id_reserva,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado_reserva,
    r.id_habitacion,
    r.id_huesped
FROM reserva AS r
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT @p30_page_size;

-- Página siguiente: reemplazar las variables por el último registro recibido en la página anterior.
SET @p30_ultima_fecha_inicio = DATE('2023-06-01');
SET @p30_ultimo_id_reserva = 123456;

SELECT
    r.id_reserva,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado_reserva,
    r.id_habitacion,
    r.id_huesped
FROM reserva AS r
WHERE (r.fecha_inicio, r.id_reserva) > (@p30_ultima_fecha_inicio, @p30_ultimo_id_reserva)
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT @p30_page_size;
