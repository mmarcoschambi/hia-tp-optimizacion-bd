# Parte IX y X corregidas — Puntos 43 a 52 (listo para pegar en Word)

> Base: `hotel_db`, MariaDB 10.6.23, motor InnoDB, `innodb_buffer_pool_size` 128 MiB.
> DDL real del laboratorio (4 tablas): `Hotel`, `Habitacion`, `Huesped`, `Reserva`.
> `Reserva` ≈ 6.000.000 filas; `Habitacion` vacía (0 filas); `Hotel`/`Huesped` vacías.
> NO existe `tipo_habitacion`. Todo tiempo es `[MEDIR]`: ningún número de esta parte
> se afirma sin ejecutar el comando indicado.

---

## Punto 43 — Configuración del servidor (my.cnf / my.ini)

El archivo principal de configuración es `my.cnf` (Linux) o `my.ini` (Windows).
Parámetros clave para este laboratorio (MariaDB 10.6.23, InnoDB):

- **`innodb_buffer_pool_size`**: caché de datos e índices InnoDB. En este laboratorio
  vale 128 MiB (valor por defecto de la instalación). Verificar con
  `SELECT @@innodb_buffer_pool_size;`. En producción se dimensiona según la RAM
  real del servidor; aquí NO se cambia, solo se mide.
- **`max_connections`**: tope de conexiones concurrentes (cada conexión consume memoria).
- **`sort_buffer_size` y `join_buffer_size`**: memoria por conexión para `ORDER BY`
  y joins sin índice adecuado.
- **`tmp_table_size` y `max_heap_table_size`**: tope de tablas temporales en RAM;
  si se supera, la temporal cae a disco y la consulta se degrada.

Comandos:

```sql
SELECT VERSION();
SELECT @@innodb_buffer_pool_size / 1024 / 1024 AS buffer_pool_mib;
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
```

[MEDIR] Pegar salida de los 3 comandos.

## Punto 44 — InnoDB Buffer Pool

El Buffer Pool divide la RAM en páginas de 16 KB. *Cache Hit* = la página ya está
en RAM (rápido); *Cache Miss* (*Cold Cache*) = hay que leerla de disco (lento).
Con `Reserva` de ~6M filas y solo 128 MiB de pool, los índices no entran completos
en memoria: los rangos grandes pagan I/O físico. Por eso las mediciones se repiten
con caché fría y caliente y se informa el pool junto a cada tiempo.

Comando: `SELECT @@innodb_buffer_pool_size;` + `SHOW VARIABLES LIKE 'datadir';`.

[MEDIR] Tamaño del pool + tiempo de la misma consulta en frío vs. caliente.

## Punto 45 — Cuellos de botella (CPU, disco y red)

- **Limitado por disco (I/O Bound)**: escaneos completos (*Full Table Scan*, `type = ALL`)
  sobre millones de filas por falta de índice o filtro no SARGable.
- **Limitado por CPU (CPU Bound)**: agregaciones (`COUNT`, `SUM`), `DATEDIFF`,
  `GROUP BY` masivos que procesan en memoria.
- **Limitado por red (Network Bound)**: `SELECT *` o consultas sin `LIMIT` que
  transfieren datos innecesarios.

Todo el diagnóstico se hace con MariaDB 10.6.23: `EXPLAIN` (plan estimado) y
`ANALYZE SELECT` (plan + tiempo real). No existe `EXPLAIN ANALYZE` en esta versión.

[MEDIR] `ANALYZE SELECT` de la consulta problema (pegar `type`, `rows`, tiempo).

## Punto 46 — Connection Pool (directa vs. pool)

Cada conexión directa nueva paga handshake TCP + autenticación + estructuras por
conexión. Bajo concurrencia ese costo domina. Un pool mantiene conexiones
preestablecidas y reutilizables: elimina el handshake por consulta y acota el
consumo del servidor.

La medición vive en el script ya existente `bench_pool.py` (100 SELECT simples
en 3 modos: conexión por consulta / conexión reutilizada / pool size=5).

Comando:

```text
python bench_pool.py
```

[MEDIR] Pegar la tabla de 3 modos (total_ms, prom_ms, mín, máx) con caché fría y caliente.

## Punto 47 — Slow Query Log y diagnóstico

Activación y lectura (MariaDB 10.6.23):

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
-- SET GLOBAL log_queries_not_using_indexes = ON;  -- solo si el usuario tiene SUPER
```

`log_queries_not_using_indexes` solo se activa si el usuario tiene privilegio
`SUPER`; si devuelve error de privilegios, se omite y se deja constancia.
Luego se ejecuta una consulta real (ver `parte_x_corregido.sql`, Sec 5) y se lee
lo capturado:

```sql
SELECT start_time, query_time, rows_examined, sql_text
FROM mysql.slow_log
ORDER BY start_time DESC
LIMIT 10;
```

Si `slow_log` sale vacía, revisar `SHOW VARIABLES LIKE 'slow_query_log%';`
y el valor de `long_query_time`.

[MEDIR] Pegar la(s) fila(s) capturada(s): `query_time`, `rows_examined`, texto SQL.

## Punto 48 — Mantenimiento preventivo (ANALYZE / OPTIMIZE TABLE)

1. **`ANALYZE TABLE Reserva;`**: actualiza estadísticas de cardinalidad para que el
   optimizador elija el mejor plan. Barato y seguro; correr antes de los `EXPLAIN`
   finales.
2. **`OPTIMIZE TABLE Reserva;`**: reconstruye la tabla y desfragmenta los B-Tree.
   Con ~6M filas tarda varios minutos y bloquea: solo en ventana de mantenimiento
   o sobre copia descartable, nunca en horario de uso.

```sql
ANALYZE TABLE Reserva;
-- OPTIMIZE TABLE Reserva;  -- solo en mantenimiento / copia
```

[MEDIR] `ANALYZE TABLE` + `SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY
FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'hotel_db'
AND TABLE_NAME = 'Reserva';` antes y después de la carga masiva.

## Punto 49 — Escalabilidad vertical vs. horizontal

- **Vertical (Scale-Up)**: más RAM, más núcleos, SSD/NVMe en el mismo servidor.
  Ventaja: sin cambiar SQL ni arquitectura. Límite: tope físico y costo.
  En este TP equivale a subir el Buffer Pool o el disco; no se hace, solo se mide
  con 128 MiB.
- **Horizontal (Scale-Out)**: réplicas de lectura o *sharding* entre nodos.
  Ventaja: crecimiento casi ilimitado. Costo: complejidad de consistencia (ACID
  distribuido). Fuera del alcance de este laboratorio de un solo nodo.

[MEDIR] Registrar RAM, CPU y disco del equipo (ver tabla de cierre).

## Punto 50 — Particionamiento RANGE por fecha

Estrategia: `PARTITION BY RANGE (TO_DAYS(fecha_inicio))` con 5 particiones
(`p_historico`, `p_2023`, `p_2024`, `p_2025`, `p_futuro`). Se usa `TO_DAYS()`
—no `YEAR()`— porque la función de partición debe ser monótona y permitir
*pruning* por rango.

Dos advertencias obligatorias:

1. **FK impiden particionar (error 1503 de InnoDB).** Hay que eliminar primero
   las FK de `Reserva` (ver nombres reales con `SHOW CREATE TABLE Reserva;`).
2. **La PK debe incluir la columna de partición.** Se cambia
   `PRIMARY KEY (id_reserva)` por `PRIMARY KEY (id_reserva, fecha_inicio)`.

El `ALTER` sobre ~6M filas tarda varios minutos y bloquea la tabla: hacerlo en
copia descartable (`Reserva_part`, recomendado) o en ventana de mantenimiento.
Sentencias completas —comentadas por defecto— en `parte_x_corregido.sql`, Sec 2.

[MEDIR] `SHOW CREATE TABLE Reserva;` (o `Reserva_part`) + `SELECT PARTITION_NAME,
TABLE_ROWS FROM information_schema.PARTITIONS WHERE TABLE_SCHEMA = 'hotel_db'
AND TABLE_NAME = 'Reserva';` tras particionar.

## Punto 51 — Partition Pruning

*Pruning* = el optimizador descarta las particiones que no cumplen el `WHERE` y
lee solo las necesarias. Condición: filtro SARGable con `>=` y `<` (límite
superior exclusivo), nunca `YEAR(col)` ni `BETWEEN` cerrado sobre fechas.

Demostración con el rango junio–diciembre 2023 (ver `parte_x_corregido.sql`,
Sec 1 y 3):

```sql
EXPLAIN SELECT id_reserva, fecha_inicio, fecha_fin, estado_reserva
FROM Reserva
WHERE fecha_inicio >= '2023-06-01'
  AND fecha_inicio < '2024-01-01'
LIMIT 100;
```

Qué mirar: **columna `partitions` del `EXPLAIN`** (MariaDB la muestra siempre;
NO existe `EXPLAIN PARTITIONS` en 10.6). Valor esperado con partición:
`p_2023` (una sola). Sin particionar: `NULL`/vacío. Se compara tiempo y `rows`
antes vs. después, ambos con `[MEDIR]`; no se afirma ningún porcentaje fijo
(el "80 %" de versiones anteriores queda eliminado por no medido).

[MEDIR] `EXPLAIN` (columna `partitions`, `type`, `rows`) + `ANALYZE SELECT`
(tiempo) del mismo rango, con y sin particionar.

## Punto 52 — Vistas y tabla resumen (solo-Reserva)

MariaDB no tiene `CREATE MATERIALIZED VIEW`: se usa tabla resumen + vista que
la expone. La resumen es **solo sobre `Reserva`** porque `Habitacion`/`Hotel`
están vacías (cualquier `JOIN` devolvería 0 filas) y `tipo_habitacion` no existe:

```sql
CREATE TABLE IF NOT EXISTS vista_mat_resumen_mensual (
    anio INT NOT NULL,
    mes INT NOT NULL,
    total_reservas INT NOT NULL,
    noches_totales BIGINT NOT NULL,
    PRIMARY KEY (anio, mes)
);
```

Refresco batch y vista (detalle en `parte_x_corregido.sql`, Sec 4):

```sql
REPLACE INTO vista_mat_resumen_mensual (anio, mes, total_reservas, noches_totales)
SELECT YEAR(fecha_inicio), MONTH(fecha_inicio), COUNT(*),
       SUM(DATEDIFF(fecha_fin, fecha_inicio))
FROM Reserva
WHERE estado_reserva IN ('Confirmada', 'Finalizada')
GROUP BY YEAR(fecha_inicio), MONTH(fecha_inicio);

CREATE OR REPLACE VIEW v_resumen_mensual AS
SELECT * FROM vista_mat_resumen_mensual;
```

La consulta de reporte (`SELECT * FROM vista_mat_resumen_mensual WHERE anio = 2023`)
lee ~12 filas en lugar de 6M.

Otras estrategias de particionamiento (cuándo conviene cada una):

| Estrategia | Cuándo conviene |
|---|---|
| `RANGE` (la usada) | Rangos temporales o numéricos con *pruning* por `WHERE` de rango |
| `LIST` | Valores discretos conocidos (p. ej. `estado_reserva` con pocos valores) |
| `HASH` | Distribuir carga uniformemente sin *pruning* por rango (solo igualdad) |
| `KEY` | Como `HASH` pero con función propia de MySQL/MariaDB (reparto interno) |

[MEDIR] `ANALYZE SELECT * FROM vista_mat_resumen_mensual WHERE anio = 2023;`
(tiempo) vs. agregación directa sobre `Reserva` del mismo año (tiempo).

---

## Cierre — lista [MEDIR] 43–52 (comando exacto cada uno)

| Punto | Dato | Comando exacto |
|---|---|---|
| 43 | Versión + pool | `SELECT VERSION();` y `SELECT @@innodb_buffer_pool_size;` en `mysql hotel_db` |
| 44 | Pool frío vs. caliente | Misma `ANALYZE SELECT` 2 veces seguidas (pegar ambos tiempos) |
| 45 | Plan problema | `EXPLAIN` + `ANALYZE SELECT` de la consulta lenta (pegar `type`, `rows`, tiempo) |
| 46 | Pool conexiones | `python bench_pool.py` (pegar tabla 3 modos) |
| 47 | Slow log | `SELECT start_time, query_time, rows_examined, sql_text FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;` |
| 48 | Estadísticas | `ANALYZE TABLE Reserva;` + `SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'hotel_db' AND TABLE_NAME = 'Reserva';` |
| 49 | Hardware | `SHOW VARIABLES LIKE 'datadir';` + RAM/CPU/disco del SO (ver informe Parte V–VI, P22) |
| 50 | Particiones | `SELECT PARTITION_NAME, TABLE_ROWS FROM information_schema.PARTITIONS WHERE TABLE_SCHEMA = 'hotel_db' AND TABLE_NAME = 'Reserva';` |
| 51 | Pruning | `EXPLAIN` (columna `partitions`) + `ANALYZE SELECT` del rango 2023, con y sin particionar |
| 52 | Resumen | `ANALYZE SELECT * FROM vista_mat_resumen_mensual WHERE anio = 2023;` vs. agregación directa sobre `Reserva` |
