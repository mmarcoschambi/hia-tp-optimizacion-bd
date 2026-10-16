# PARTE V — Consultas de negocio (P24 a P28)

> Base: `hotel_db`, motor InnoDB, MariaDB 10.6.23.
> DDL REAL del laboratorio (Punto 6, 4 tablas simplificadas). Todo el SQL de esta parte corre sobre este DDL y ningún otro:
>
> - `Hotel(id_hotel INT AUTO_INCREMENT PK, nombre VARCHAR(100), ciudad VARCHAR(100), direccion VARCHAR(150), estrellas INT CHECK (estrellas BETWEEN 1 AND 5))`
> - `Habitacion(id_habitacion INT AUTO_INCREMENT PK, id_hotel INT FK → Hotel(id_hotel) ON DELETE CASCADE, numero_habitacion VARCHAR(10), tipo VARCHAR(50), precio_noche DECIMAL(10,2), estado VARCHAR(20) DEFAULT 'Disponible')`
> - `Huesped(id_huesped INT AUTO_INCREMENT PK, nombre VARCHAR(60), apellido VARCHAR(60), dni VARCHAR(20) UNIQUE, telefono VARCHAR(30), email VARCHAR(100))`
> - `Reserva(id_reserva INT AUTO_INCREMENT PK, id_habitacion INT FK → Habitacion, id_huesped INT FK → Huesped, fecha_inicio DATE, fecha_fin DATE, estado_reserva VARCHAR(30) DEFAULT 'Confirmada')`
>
> NO existen en el laboratorio: `tipo_habitacion`, `nombre_hotel`, `nombre_tipo`, `fecha_salida`, `tarifa_aplicada`. Donde se necesita precio se usa `habitacion.precio_noche` y `habitacion.tipo`. Donde se necesita hotel se usa `hotel.nombre`.
>
> Contexto de datos del laboratorio: `reserva` ≈ 6.000.000 filas (carga con `FOREIGN_KEY_CHECKS=0`, `id_habitacion` aleatorio 1–5000, `id_huesped` aleatorio 1–500000, `fecha_inicio` = 2023-01-01 + 0–1000 días, estadía 1–7 días, estados 65 % Finalizada / 20 % Confirmada / 15 % Cancelada). `habitacion` vacía (0 filas); `hotel`/`huesped` presuntamente vacías. En consecuencia, toda consulta con `INNER JOIN` a `habitacion`/`hotel`/`huesped` devuelve 0 filas en este laboratorio, aunque el SQL sea correcto. Se indica con `NOTA LAB` donde corresponde.
>
> Convención de parámetros: `:inicio`, `:fin`, `:id` son parámetros (en `mysql` se reemplazan por literales o variables `@inicio`, `@fin`). Los rangos temporales son siempre SARGables con `>=` y `<` (límite superior exclusivo), nunca `BETWEEN` cerrado sobre fechas ni `YEAR(col)` en el filtro principal.

---

## P24 — Consultas progresivas (simple → JOIN → agregación → subconsulta)

### P24.1 — Consulta simple: reservas confirmadas en un rango

Enunciado: listar las reservas con estado `Confirmada` cuya `fecha_inicio` cae dentro del rango `[:inicio, :fin)`.

```sql
SELECT r.id_reserva, r.id_habitacion, r.id_huesped,
       r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.estado_reserva = 'Confirmada'
  AND r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Qué demuestra: filtro SARGable por rango + estado, base de todos los análisis posteriores.

### P24.2 — Consulta con JOIN: reservas del rango con datos del huésped

Enunciado: para el mismo rango, traer cada reserva junto con nombre, apellido y email del huésped.

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva,
       h.nombre, h.apellido, h.email
FROM Reserva AS r
INNER JOIN Huesped AS h ON h.id_huesped = r.id_huesped
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Qué demuestra: JOIN por clave foránea `Reserva → Huesped` con recorte previo por fecha.

NOTA LAB: devuelve 0 filas en este laboratorio porque `huesped` está vacía; el SQL es correcto con maestras cargadas.

### P24.3 — Agregación: volumen y noches por estado en el rango

Enunciado: para el rango `[:inicio, :fin)`, contar reservas y sumar noches por cada `estado_reserva`.

```sql
SELECT r.estado_reserva,
       COUNT(*) AS total_reservas,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales,
       AVG(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS estadia_media_noches
FROM Reserva AS r
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY r.estado_reserva
ORDER BY total_reservas DESC;
```

Qué demuestra: agregación `GROUP BY` sobre el subconjunto recortado por rango (solo toca `reserva`).

### P24.4 — Subconsulta: huéspedes con más reservas que el promedio del rango

Enunciado: huéspedes cuya cantidad de reservas en el rango supera el promedio de reservas por huésped del mismo rango.

```sql
SELECT r.id_huesped, COUNT(*) AS total_reservas
FROM Reserva AS r
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY r.id_huesped
HAVING COUNT(*) > (
    SELECT AVG(t.cnt)
    FROM (
        SELECT COUNT(*) AS cnt
        FROM Reserva AS r2
        WHERE r2.fecha_inicio >= :inicio
          AND r2.fecha_inicio < :fin
        GROUP BY r2.id_huesped
    ) AS t
)
ORDER BY total_reservas DESC
LIMIT 100;
```

Qué demuestra: subconsulta agregada como umbral dinámico (`HAVING` contra promedio del mismo período).

---

## P25 — Consultas complejas de negocio (C1–C15)

> Todas usan exclusivamente columnas del DDL real. Las que combinan las 4 tablas (`hotel` + `habitacion` + `huesped` + `reserva`) se marcan `[4 TABLAS]`.

### C1 — Disponibilidad puntual: habitaciones libres en una fecha dada [4 TABLAS]

Enunciado: habitaciones (con su hotel) que NO tienen ninguna reserva activa que cubra la fecha `:fecha`.

```sql
SELECT ha.id_habitacion, ha.numero_habitacion, ha.tipo, ha.precio_noche,
       ho.nombre AS hotel, ho.ciudad
FROM Habitacion AS ha
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE NOT EXISTS (
    SELECT 1
    FROM Reserva AS r
    WHERE r.id_habitacion = ha.id_habitacion
      AND r.estado_reserva <> 'Cancelada'
      AND r.fecha_inicio <= :fecha
      AND r.fecha_fin > :fecha
)
ORDER BY ho.nombre, ha.numero_habitacion;
```

Qué demuestra: disponibilidad por anti-join (`NOT EXISTS`) con solapamiento de rango.

NOTA LAB: devuelve 0 filas en este laboratorio porque `habitacion` está vacía.

### C2 — Reservas por período con huésped y habitación

Enunciado: reservas con `fecha_inicio` en `[:inicio, :fin)`, con huésped, número y tipo de habitación.

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva,
       h.nombre, h.apellido,
       ha.numero_habitacion, ha.tipo, ha.precio_noche
FROM Reserva AS r
INNER JOIN Huesped AS h ON h.id_huesped = r.id_huesped
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Qué demuestra: recorte por rango antes de los JOIN (el filtro va sobre `reserva`).

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías (`habitacion`, `huesped`).

### C3 — Hoteles con más reservas en el período [4 TABLAS]

Enunciado: ranking de hoteles por cantidad de reservas cuya `fecha_inicio` cae en `[:inicio, :fin)`.

```sql
SELECT ho.id_hotel, ho.nombre AS hotel, ho.ciudad,
       COUNT(*) AS total_reservas
FROM Reserva AS r
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY ho.id_hotel, ho.nombre, ho.ciudad
ORDER BY total_reservas DESC
LIMIT 50;
```

Qué demuestra: agregación a nivel hotel navegando `reserva → habitacion → hotel`.

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías.

### C4 — Huéspedes con más reservas (top general, solo `reserva` + `huesped`)

Enunciado: top 100 huéspedes por cantidad total de reservas, con cancelaciones.

```sql
SELECT r.id_huesped, h.nombre, h.apellido,
       COUNT(*) AS total_reservas,
       SUM(r.estado_reserva = 'Cancelada') AS cancelaciones
FROM Reserva AS r
INNER JOIN Huesped AS h ON h.id_huesped = r.id_huesped
GROUP BY r.id_huesped, h.nombre, h.apellido
ORDER BY total_reservas DESC
LIMIT 100;
```

Qué demuestra: ranking de clientes por volumen con agregación condicional.

NOTA LAB: devuelve 0 filas en este laboratorio porque `huesped` está vacía.

### C5 — Ocupación por hotel en un período (solapamiento) [4 TABLAS]

Enunciado: noches ocupadas por hotel considerando reservas que solapan `[:inicio, :fin)` (aunque empiecen antes).

```sql
SELECT ho.id_hotel, ho.nombre AS hotel,
       COUNT(*) AS reservas_que_solapan,
       SUM(DATEDIFF(
           LEAST(r.fecha_fin, :fin),
           GREATEST(r.fecha_inicio, :inicio)
       )) AS noches_ocupadas
FROM Reserva AS r
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
  AND r.fecha_inicio < :fin
  AND r.fecha_fin > :inicio
GROUP BY ho.id_hotel, ho.nombre
ORDER BY noches_ocupadas DESC;
```

Qué demuestra: ocupación por intersección de intervalos (`LEAST`/`GREATEST`), no por `fecha_inicio` contenida.

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías.

### C6 — Ranking de habitaciones por ingreso estimado (`noches × precio_noche`)

Enunciado: top de habitaciones por ingreso estimado en no canceladas del período.

```sql
SELECT ha.id_habitacion, ha.numero_habitacion, ha.tipo,
       COUNT(*) AS reservas,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio) * ha.precio_noche) AS ingreso_estimado
FROM Reserva AS r
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
  AND r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY ha.id_habitacion, ha.numero_habitacion, ha.tipo
ORDER BY ingreso_estimado DESC
LIMIT 100;
```

Qué demuestra: valorización con `precio_noche` de `habitacion` (no existe tarifa en `reserva`).

NOTA LAB: devuelve 0 filas en este laboratorio porque `habitacion` está vacía.

### C7 — Análisis temporal: reservas por mes (serie 2023–2025, solo `reserva`)

Enunciado: cantidad de reservas y noches por mes de `fecha_inicio`, con tasa de cancelación.

```sql
SELECT DATE_FORMAT(r.fecha_inicio, '%Y-%m') AS mes,
       COUNT(*) AS total_reservas,
       SUM(r.estado_reserva = 'Cancelada') AS canceladas,
       ROUND(100 * SUM(r.estado_reserva = 'Cancelada') / COUNT(*), 2) AS tasa_cancelacion_pct,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales
FROM Reserva AS r
WHERE r.fecha_inicio >= '2023-01-01'
  AND r.fecha_inicio < '2026-01-01'
GROUP BY DATE_FORMAT(r.fecha_inicio, '%Y-%m')
ORDER BY mes;
```

Qué demuestra: serie temporal mensual con agregación condicional (solo `reserva`, sí devuelve filas: ~6M).

### C8 — Huéspedes con cancelaciones repetidas y actividad posterior (EXISTS)

Enunciado: huéspedes con 3 o más cancelaciones desde `:inicio` que además tienen alguna reserva no cancelada posterior a una de sus cancelaciones.

```sql
SELECT h.id_huesped, h.nombre, h.apellido,
       COUNT(*) AS cancelaciones_periodo,
       MIN(r.fecha_inicio) AS primera_cancelacion,
       MAX(r.fecha_inicio) AS ultima_cancelacion
FROM Huesped AS h
INNER JOIN Reserva AS r ON r.id_huesped = h.id_huesped
WHERE r.estado_reserva = 'Cancelada'
  AND r.fecha_inicio >= :inicio
  AND EXISTS (
      SELECT 1
      FROM Reserva AS r_ok
      WHERE r_ok.id_huesped = h.id_huesped
        AND r_ok.estado_reserva IN ('Confirmada', 'Finalizada')
        AND r_ok.fecha_inicio > r.fecha_inicio
  )
GROUP BY h.id_huesped, h.nombre, h.apellido
HAVING COUNT(*) >= 3
ORDER BY cancelaciones_periodo DESC;
```

Qué demuestra: patrón de cancelación con subconsulta correlacionada `EXISTS`.

NOTA LAB: devuelve 0 filas en este laboratorio porque `huesped` está vacía.

### C9 — Segmentación de clientes con CASE (solo `reserva` + `huesped`)

Enunciado: clasificar huéspedes del período en Sin actividad / Riesgo alto / Premium / Frecuente / Ocasional.

```sql
SELECT h.id_huesped, h.nombre, h.apellido,
       COUNT(r.id_reserva) AS total_reservas,
       SUM(r.estado_reserva = 'Cancelada') AS cancelaciones,
       CASE
           WHEN COUNT(r.id_reserva) = 0 THEN 'Sin actividad'
           WHEN SUM(r.estado_reserva = 'Cancelada') / COUNT(*) >= 0.50 THEN 'Riesgo alto de cancelacion'
           WHEN COUNT(r.id_reserva) >= 10 THEN 'Cliente premium'
           WHEN COUNT(r.id_reserva) BETWEEN 3 AND 9 THEN 'Cliente frecuente'
           ELSE 'Cliente ocasional'
       END AS segmento
FROM Huesped AS h
LEFT JOIN Reserva AS r ON r.id_huesped = h.id_huesped
  AND r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY h.id_huesped, h.nombre, h.apellido
ORDER BY total_reservas DESC;
```

Qué demuestra: segmentación con `CASE` sobre métricas agregadas y `LEFT JOIN` con rango.

NOTA LAB: con `huesped` vacía devuelve 0 filas; con maestras cargadas clasifica correctamente.

### C10 — Hoteles: tarifa media y estadía media por tipo de habitación [4 TABLAS]

Enunciado: por hotel y `habitacion.tipo`, precio medio, estadía media y reservas no canceladas del período.

```sql
SELECT ho.nombre AS hotel, ha.tipo,
       COUNT(*) AS reservas,
       ROUND(AVG(ha.precio_noche), 2) AS precio_medio_noche,
       ROUND(AVG(DATEDIFF(r.fecha_fin, r.fecha_inicio)), 2) AS estadia_media_noches,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio) * ha.precio_noche) AS ingreso_estimado
FROM Reserva AS r
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
  AND r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY ho.nombre, ha.tipo
ORDER BY ingreso_estimado DESC;
```

Qué demuestra: doble nivel de agregación hotel × tipo usando `habitacion.tipo` (no existe tabla de tipos).

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías.

### C11 — Reservas futuras vs. históricas respecto de una fecha de corte (solo `reserva`)

Enunciado: conteo de reservas históricas (`fecha_inicio` < `:corte`) vs. futuras (`fecha_inicio` >= `:corte`) por estado.

```sql
SELECT CASE WHEN r.fecha_inicio < :corte THEN 'Historica' ELSE 'Futura' END AS horizonte,
       r.estado_reserva,
       COUNT(*) AS total_reservas
FROM Reserva AS r
GROUP BY CASE WHEN r.fecha_inicio < :corte THEN 'Historica' ELSE 'Futura' END,
         r.estado_reserva
ORDER BY horizonte, total_reservas DESC;
```

Qué demuestra: partición histórica/futura con un único parámetro de corte (sí devuelve filas: ~6M).

### C12 — Reservas por ciudad del hotel [4 TABLAS]

Enunciado: reservas y noches por ciudad del hotel en el período (usa `hotel.ciudad`).

```sql
SELECT ho.ciudad,
       COUNT(*) AS total_reservas,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales
FROM Reserva AS r
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY ho.ciudad
ORDER BY total_reservas DESC;
```

Qué demuestra: análisis geográfico navegando hasta `hotel.ciudad`.

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías.

### C13 — Huéspedes sin reservas en el período (anti-join, `huesped` + `reserva`)

Enunciado: huéspedes que no tienen ninguna reserva con `fecha_inicio` en `[:inicio, :fin)`.

```sql
SELECT h.id_huesped, h.nombre, h.apellido, h.email
FROM Huesped AS h
WHERE NOT EXISTS (
    SELECT 1
    FROM Reserva AS r
    WHERE r.id_huesped = h.id_huesped
      AND r.fecha_inicio >= :inicio
      AND r.fecha_inicio < :fin
)
ORDER BY h.apellido, h.nombre
LIMIT 200;
```

Qué demuestra: anti-join `NOT EXISTS` para inactividad en ventana (complemento de C9).

NOTA LAB: con `huesped` vacía devuelve 0 filas.

### C14 — Top huéspedes por noches con detalle de hotel [4 TABLAS]

Enunciado: top 100 huéspedes por noches en no canceladas del período, con cantidad de hoteles distintos visitados.

```sql
SELECT h.id_huesped, h.nombre, h.apellido,
       COUNT(*) AS reservas,
       SUM(DATEDIFF(r.fecha_fin, r.fecha_inicio)) AS noches_totales,
       COUNT(DISTINCT ho.id_hotel) AS hoteles_distintos
FROM Reserva AS r
INNER JOIN Huesped AS h ON h.id_huesped = r.id_huesped
INNER JOIN Habitacion AS ha ON ha.id_habitacion = r.id_habitacion
INNER JOIN Hotel AS ho ON ho.id_hotel = ha.id_hotel
WHERE r.estado_reserva IN ('Confirmada', 'Finalizada')
  AND r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY h.id_huesped, h.nombre, h.apellido
ORDER BY noches_totales DESC
LIMIT 100;
```

Qué demuestra: métrica de fidelidad/movilidad (noches + hoteles distintos) con las 4 tablas.

NOTA LAB: devuelve 0 filas en este laboratorio por maestras vacías.

### C15 — Tasa de cancelación por mes con filtro de soporte (solo `reserva`)

Enunciado: meses del período con al menos 1000 reservas, ordenados por tasa de cancelación descendente.

```sql
SELECT DATE_FORMAT(r.fecha_inicio, '%Y-%m') AS mes,
       COUNT(*) AS total_reservas,
       ROUND(100 * SUM(r.estado_reserva = 'Cancelada') / COUNT(*), 2) AS tasa_cancelacion_pct
FROM Reserva AS r
WHERE r.fecha_inicio >= :inicio
  AND r.fecha_inicio < :fin
GROUP BY DATE_FORMAT(r.fecha_inicio, '%Y-%m')
HAVING COUNT(*) >= 1000
ORDER BY tasa_cancelacion_pct DESC;
```

Qué demuestra: `GROUP BY` + `HAVING` con umbral de soporte para que la tasa sea significativa (sí devuelve filas).

---

## P26 — Disponibilidad por superposición de rangos

Una habitación está ocupada en `[:inicio, :fin)` si existe alguna reserva NO cancelada de esa habitación cuyo intervalo solapa la ventana. Dos intervalos `[a, b)` y `[c, d)` se solapan si y solo si `a < d AND c < b`. Por eso la condición canónica usa `r.fecha_inicio < :fin AND r.fecha_fin > :inicio`: captura también reservas que empiezan antes de `:inicio` pero terminan dentro, y las que empiezan dentro pero terminan después. El filtro por `fecha_inicio` contenida (`fecha_inicio BETWEEN :inicio AND :fin`) es incorrecto para ocupación porque pierde ambos bordes. Se excluye `estado_reserva = 'Cancelada'` porque una reserva cancelada no bloquea la habitación.

SQL canónico (habitaciones libres en la ventana):

```sql
SELECT ha.id_habitacion, ha.numero_habitacion, ha.tipo, ha.precio_noche
FROM Habitacion AS ha
WHERE NOT EXISTS (
    SELECT 1
    FROM Reserva AS r
    WHERE r.id_habitacion = ha.id_habitacion
      AND r.estado_reserva <> 'Cancelada'
      AND r.fecha_inicio < :fin
      AND r.fecha_fin > :inicio
)
ORDER BY ha.id_habitacion;
```

Variante por habitación (¿está libre la habitación `:id` en la ventana? Devuelve 1 fila si está libre, 0 si está ocupada):

```sql
SELECT ha.id_habitacion, ha.numero_habitacion
FROM Habitacion AS ha
WHERE ha.id_habitacion = :id
  AND NOT EXISTS (
      SELECT 1
      FROM Reserva AS r
      WHERE r.id_habitacion = ha.id_habitacion
        AND r.estado_reserva <> 'Cancelada'
        AND r.fecha_inicio < :fin
        AND r.fecha_fin > :inicio
  );
```

Variante por tipo (tipos con al menos una habitación libre en la ventana, con cantidad):

```sql
SELECT ha.tipo, COUNT(*) AS habitaciones_libres
FROM Habitacion AS ha
WHERE NOT EXISTS (
    SELECT 1
    FROM Reserva AS r
    WHERE r.id_habitacion = ha.id_habitacion
      AND r.estado_reserva <> 'Cancelada'
      AND r.fecha_inicio < :fin
      AND r.fecha_fin > :inicio
)
GROUP BY ha.tipo
ORDER BY habitaciones_libres DESC;
```

NOTA LAB: las tres variantes devuelven 0 filas (o conjunto vacío) en este laboratorio porque `habitacion` está vacía; la lógica es correcta con maestras cargadas. Índice sugerido para la subconsulta: `CREATE INDEX idx_reserva_habitacion_rango ON Reserva(id_habitacion, fecha_inicio, fecha_fin, estado_reserva);` [MEDIR: verificar con `SHOW INDEX FROM Reserva;`].

---

## P27 — Históricas / futuras / por mes-año + comparativa SARGable

Históricas (terminaron antes de la fecha de corte `:corte`):

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.fecha_fin <= :corte
ORDER BY r.fecha_inicio DESC, r.id_reserva DESC
LIMIT 200;
```

Futuras (empiezan en o después de `:corte`):

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.fecha_inicio >= :corte
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Por mes-año (marzo 2024, SARGable con límite superior exclusivo):

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.fecha_inicio >= '2024-03-01'
  AND r.fecha_inicio < '2024-04-01'
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Comparativa SARGable vs. no SARGable (mismo resultado lógico, distinto plan). Versión SARGable (permite `range`/`ref` sobre índice de `fecha_inicio`):

```sql
ANALYZE SELECT r.id_reserva, r.fecha_inicio
FROM Reserva AS r
WHERE r.fecha_inicio >= '2024-01-01'
  AND r.fecha_inicio < '2025-01-01';
```

Versión no SARGable (la función sobre la columna impide usar el índice de rango; fuerza evaluación fila por fila):

```sql
ANALYZE SELECT r.id_reserva, r.fecha_inicio
FROM Reserva AS r
WHERE YEAR(r.fecha_inicio) = 2024;
```

Qué mirar en la salida de `ANALYZE SELECT` (MariaDB 10.6.23, sin `EXPLAIN ANALYZE`): columna `type` (`ALL` = escaneo completo en la versión con `YEAR()` frente a `range` o `ref` en la SARGable si existe índice sobre `fecha_inicio`), columna `rows` (filas estimadas a examinar, mucho mayor en la no SARGable), columna `Extra` (`Using where` con o sin `Using index condition`; la versión con función no puede hacer *range access* sobre el índice) y tiempo `r_total_time_ms` del `ANALYZE` (mayor en la no SARGable). [MEDIR: ejecutar ambas sentencias con `ANALYZE FORMAT=JSON SELECT ...` y copiar `type`, `rows`, `Extra` y tiempo real; comando: `mysql -u root -p hotel_db`.]

---

## P28 — SELECT * vs. columnas + paginación OFFSET alto vs. keyset

### SELECT * vs. lista de columnas

Evitar `SELECT *`:

```sql
-- Costoso: transporta todas las columnas aunque no se necesiten.
SELECT * FROM Reserva WHERE id_huesped = 42 LIMIT 100;
```

```sql
-- Eficiente: solo las columnas necesarias; permite covering index y menos bytes por fila.
SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE id_huesped = 42
LIMIT 100;
```

Qué mirar: con `ANALYZE SELECT` la proyección estrecha reduce tiempo y bytes; si existe índice que cubre las columnas pedidas, `Extra` muestra `Using index` (índice cobertor) en lugar de acceso a la fila. [MEDIR: `ANALYZE FORMAT=JSON SELECT ...` de ambas y comparar tiempo y `Extra`; más `SHOW VARIABLES LIKE 'innodb_buffer_pool_size';` para contexto.]

### Paginación: OFFSET alto vs. keyset

OFFSET alto (obliga al motor a leer y descartar 500.000 filas en cada página):

```sql
SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
ORDER BY fecha_inicio, id_reserva
LIMIT 100 OFFSET 500000;
```

Keyset (usa la última clave vista; acceso por rango indexado, costo constante por página):

```sql
-- Primera página
SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
ORDER BY fecha_inicio, id_reserva
LIMIT 100;
-- Páginas siguientes (:ult_fecha, :ult_id = última fila de la página anterior)
SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE (fecha_inicio, id_reserva) > (:ult_fecha, :ult_id)
ORDER BY fecha_inicio, id_reserva
LIMIT 100;
```

Índice sugerido para keyset (imprescindible para que el `ORDER BY` + filtro sea un *range* sobre índice):

```sql
CREATE INDEX idx_reserva_keyset ON Reserva (fecha_inicio, id_reserva);
```

Nota MariaDB 10.6.23: si el optimizador no resuelve el constructor de fila como *range*, usar la variante equivalente con `OR` (mismo resultado, habilita *range* en 10.6):

```sql
SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio > :ult_fecha
   OR (fecha_inicio = :ult_fecha AND id_reserva > :ult_id)
ORDER BY fecha_inicio, id_reserva
LIMIT 100;
```

[MEDIR: `ANALYZE SELECT ... LIMIT 100 OFFSET 500000;` vs. `ANALYZE SELECT ... WHERE (fecha_inicio, id_reserva) > (...) ...;` y comparar `type`, `rows`, `Extra` y tiempo; comando: `mysql -u root -p hotel_db`.]

---

# PARTE VI — Optimización: medición y SARGabilidad (inicio reordenado)

## P29 — EXPLAIN / ANALYZE SELECT con ejemplo real

Consulta de ejemplo (reservas por rango + estado, solo `reserva`, devuelve filas con 6M cargadas):

```sql
SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.estado_reserva = 'Finalizada'
  AND r.fecha_inicio >= '2024-01-01'
  AND r.fecha_inicio < '2025-01-01'
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Plan estimado:

```sql
EXPLAIN SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.estado_reserva = 'Finalizada'
  AND r.fecha_inicio >= '2024-01-01'
  AND r.fecha_inicio < '2025-01-01'
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Ejecución real con estadísticas (MariaDB 10.6: `ANALYZE SELECT`, no existe `EXPLAIN ANALYZE`):

```sql
ANALYZE SELECT r.id_reserva, r.fecha_inicio, r.fecha_fin, r.estado_reserva
FROM Reserva AS r
WHERE r.estado_reserva = 'Finalizada'
  AND r.fecha_inicio >= '2024-01-01'
  AND r.fecha_inicio < '2025-01-01'
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT 200;
```

Opcional con detalle JSON: `ANALYZE FORMAT=JSON SELECT ...` (misma consulta). En `EXPLAIN` clásico MariaDB 10.6 la salida incluye columna `partitions` (además de `id`, `select_type`, `table`, `type`, `possible_keys`, `key`, `key_len`, `ref`, `rows`, `filtered`, `Extra`).

Qué columna mirar (tabla):

| Columna | Qué indica | Valor esperado / lectura |
|---|---|---|
| `type` | Tipo de acceso | `ALL` = escaneo completo (mal); `range`/`ref` = usa índice (bien) |
| `key` | Índice elegido | Nombre del índice usado (`NULL` = ninguno) |
| `rows` | Filas estimadas a examinar | Menor = mejor; comparar antes/después de crear índice |
| `filtered` | % filtrado por `WHERE` tras acceso | Alto = el acceso ya es selectivo |
| `Extra` | Detalle operativo | `Using where`; `Using index` = cobertor; `Using filesort` = ordena fuera del índice; `Using index condition` = condición empujada al índice |
| `partitions` | Particiones accedidas (MariaDB la muestra siempre) | `NULL`/vacío = tabla no particionada (caso de este TP) |
| `r_total_time_ms` (solo `ANALYZE`) | Tiempo real medido | Comparar SARGable vs. no SARGable / con vs. sin índice |

[MEDIR: correr `EXPLAIN` + `ANALYZE SELECT` de la consulta de ejemplo y pegar `type`, `key`, `rows`, `Extra`, tiempo; comandos: `mysql -u root -p hotel_db`, `SELECT VERSION();`, `SHOW INDEX FROM Reserva;`.]

## P30 — SARGabilidad con ejemplo real

Mismo filtro de mes (marzo 2024), dos escrituras. Versión SARGable (recomendada):

```sql
ANALYZE SELECT r.id_reserva, r.fecha_inicio
FROM Reserva AS r
WHERE r.fecha_inicio >= '2024-03-01'
  AND r.fecha_inicio < '2024-04-01';
```

Versión no SARGable (misma lógica, bloquea el índice):

```sql
ANALYZE SELECT r.id_reserva, r.fecha_inicio
FROM Reserva AS r
WHERE YEAR(r.fecha_inicio) = 2024 AND MONTH(r.fecha_inicio) = 3;
```

Qué plan cambia: la versión SARGable puede resolver el predicado como *range access* sobre un índice de `fecha_inicio` (`type = range`, `rows` acotado al mes, `Extra` con `Using index condition` si aplica); la versión con `YEAR()`/`MONTH()` aplica una función sobre la columna, el optimizador no puede derivar un rango y cae a `type = ALL` con `rows` ≈ 6M y filtrado fila por fila (`Using where`). Regla general: nunca envolver la columna indexada en funciones ni aritmética en el filtro principal (`YEAR(col)`, `DATE(col) = ...`, `col + 0 = ...`, `UPPER(col) = ...`); transformar el parámetro al formato de la columna y comparar rangos SARGables.

[MEDIR: ejecutar ambas con `ANALYZE FORMAT=JSON SELECT ...` y copiar `type`, `rows`, `Extra` y tiempo de cada una.]

---

# Correcciones de texto (listas para pegar en Word)

## P5.3 — Búsqueda por índice B-Tree (párrafo corregido)

> La búsqueda por clave en un índice B-Tree tiene costo O(log n), donde n es la cantidad de entradas del índice: cada nivel del árbol reduce el espacio de búsqueda en un factor igual al fan-out (cantidad de hijos por nodo, típicamente de cientos), por lo que la altura del árbol crece logarítmicamente con n y solo se recorren tantos nodos como niveles tenga el árbol (por ejemplo, 3–4 niveles para millones de filas). Esto vale tanto para el acceso puntual por igualdad como para el inicio de un barrido por rango, que luego recorre las hojas enlazadas en orden.

## P11 — Justificación de índices con B-Tree (párrafo corregido)

> Se crean índices secundarios sobre las columnas de filtrado y ordenamiento más usadas (`fecha_inicio`, `estado_reserva`, claves foráneas y la dupla de paginación `fecha_inicio, id_reserva`) porque el motor los organiza como B-Tree: localizar la primera entrada que cumple el predicado cuesta O(log n) comparaciones y el resto del rango se recorre secuencialmente por las hojas encadenadas, en lugar de escanear las 6.000.000 de filas (O(n)). Sin índice, cada consulta por rango o estado paga un escaneo completo; con índice, el costo queda dominado por la altura del árbol más la cantidad de filas del resultado.

## P12 — Altura del B-Tree y costo logarítmico (párrafo corregido)

> Un B-Tree de fan-out alto (cientos de entradas por nodo) mantiene su altura en 3–4 niveles incluso con millones de claves, de modo que cualquier búsqueda puntual o posicionamiento para un rango recorre como máximo esa cantidad de nodos: costo O(log n). La altura crece de forma logarítmica porque cada nivel multiplica la capacidad total por el fan-out; duplicar o triplicar n agrega a lo sumo un nivel, no un recorrido proporcional a n. Por eso los índices son la principal herramienta para pasar consultas de O(n) a O(log n + k), con k = filas del resultado.

## P22 — Metodología y entorno de medición (párrafo + comandos)

> Las mediciones se realizaron sobre MariaDB 10.6.23 con motor InnoDB, base `hotel_db`, tabla `reserva` con 6.000.000 de filas generadas según el script de carga (`src/carga_masiva.py`), y `innodb_buffer_pool_size` de 128 MiB (valor por defecto de la instalación). Los planes se obtuvieron con `EXPLAIN` y los tiempos reales con `ANALYZE SELECT` (sintaxis propia de MariaDB 10.6; `EXPLAIN ANALYZE` no existe en esta versión). Cada medición se repitió con caché fría y caliente, registrando el tiempo devuelto por `ANALYZE` junto con `type`, `key`, `rows` y `Extra`.

Comandos de entorno (ejecutar y pegar salida):

```sql
SELECT VERSION();
SELECT @@innodb_buffer_pool_size / 1024 / 1024 AS buffer_pool_mib;
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'version%';
SELECT COUNT(*) FROM Reserva;
```

```text
[MEDIR] RAM total y memoria libre del equipo durante la prueba.
  Linux:  free -m
  Windows (cmd): wmic ComputerSystem get TotalPhysicalMemory /format:value  +  wmic OS get FreePhysicalMemory /format:value
[MEDIR] CPU y sistema operativo.
  Linux:  lscpu | head -20  +  uname -a
  Windows (cmd): wmic cpu get Name,NumberOfCores /format:value  +  ver
[MEDIR] Disco (tipo y espacio libre donde reside el datadir).
  Linux:  df -h  +  lsblk -d -o NAME,ROTA,MODEL (ROTA=0 SSD/NVMe, ROTA=1 HDD)
  Windows (cmd): wmic logicaldisk get DeviceID,Size,FreeSpace /format:value
  MariaDB: SHOW VARIABLES LIKE 'datadir';
```

## P5.5 — Costos de INSERT/DELETE con índices (párrafo sin valores inventados)

> Cada índice secundario agrega un B-Tree que debe mantenerse en cada escritura: un `INSERT` no solo escribe la fila, también inserta una entrada O(log n) en cada índice, y un `DELETE` debe localizar y borrar esas entradas además de la fila. Por lo tanto, a más índices secundarios, mayor costo por escritura individual y mayor amplificación de escritura, a cambio de lecturas más rápidas. La magnitud exacta depende del hardware, del tamaño de página, del buffer pool y de la cantidad de índices, por lo que no se afirma ningún tiempo sin medir: ver experimento `bench_insert_delete.sql` y tabla [MEDIR].

Comandos: `mysql -u root -p hotel_db < bench_insert_delete.sql` y copiar la tabla de tiempos impresa por el propio script.

## P7 — Tipo BOOLEAN en MariaDB (párrafo)

> En MariaDB, `BOOLEAN` (y su sinónimo `BOOL`) es un alias de `TINYINT(1)`: acepta los literales `TRUE`/`FALSE` como sinónimos de 1/0, almacena 1 byte por valor y admite cualquier entero 0–255 si no se restringe. Para una bandera estricta 0/1 se declara `TINYINT(1)` (o `BOOLEAN`) con `CHECK (col IN (0,1))` o, de forma equivalente, `CHECK (col IS TRUE OR col IS FALSE)`. En este modelo no se usa `BOOLEAN` porque los estados (`estado`, `estado_reserva`) se modelan como `VARCHAR` con dominio explícito; si se agregara una bandera (por ejemplo, `activa`), se declararía `activa BOOLEAN DEFAULT TRUE CHECK (activa IN (0,1))`.

---

# Lista [MEDIR] pendientes

| # | Dato | Comando exacto |
|---|---|---|
| 1 | Versión MariaDB | `SELECT VERSION();` en `mysql -u root -p hotel_db` |
| 2 | Tamaño buffer pool | `SELECT @@innodb_buffer_pool_size;` y `SHOW VARIABLES LIKE 'innodb_buffer_pool_size';` |
| 3 | Filas reales de `reserva` | `SELECT COUNT(*) FROM Reserva;` |
| 4 | Índices reales de `reserva` | `SHOW INDEX FROM Reserva;` |
| 5 | Plan consulta P29 | `EXPLAIN SELECT ...` de P29 (pegar `type`, `key`, `rows`, `Extra`, `partitions`) |
| 6 | Tiempo real P29 | `ANALYZE SELECT ...` de P29 (pegar tiempo + mismas columnas) |
| 7 | Comparativa SARGable P30 | `ANALYZE FORMAT=JSON SELECT ...` versión rango + versión `YEAR()` (pegar `type`, `rows`, `Extra`, tiempo de cada una) |
| 8 | Comparativa P27 mes | `ANALYZE SELECT ... >= '2024-01-01' AND ... < '2025-01-01'` vs. `YEAR(fecha_inicio)=2024` (pegar `type`, `rows`, tiempo) |
| 9 | Comparativa SELECT * P28 | `ANALYZE FORMAT=JSON SELECT * ... WHERE id_huesped = 42` vs. proyección estrecha (tiempo + `Extra`) |
| 10 | Comparativa paginación P28 | `ANALYZE SELECT ... LIMIT 100 OFFSET 500000;` vs. keyset con `(fecha_inicio,id_reserva) > (?,?)` (tiempo + `rows`) |
| 11 | Bench INSERT/DELETE | `mysql -u root -p hotel_db < bench_insert_delete.sql` (pegar tabla de tiempos A vs. B) |
| 12 | Bench pool conexiones | `python bench_pool.py` (pegar tabla 3 modos; requiere `pip install mysql-connector-python`) |
| 13 | RAM del equipo | Linux `free -m` / Windows `wmic ComputerSystem get TotalPhysicalMemory /format:value` |
| 14 | CPU y SO | Linux `lscpu \| head -20` + `uname -a` / Windows `wmic cpu get Name,NumberOfCores /format:value` + `ver` |
| 15 | Disco y datadir | `SHOW VARIABLES LIKE 'datadir';` + Linux `df -h` / Windows `wmic logicaldisk get DeviceID,Size,FreeSpace /format:value` |
| 16 | Estadísticas/tabla | `ANALYZE TABLE Reserva;` antes de los `EXPLAIN` finales + `SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='hotel_db' AND TABLE_NAME='Reserva';` |
