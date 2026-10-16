# Parte X — Particionamiento de `reserva`: resultados medidos (Puntos 49 a 51)

> Todas las cifras de este documento salen de ejecutar los comandos contra la base real
> (`hotel_db`, MariaDB 10.6.23, InnoDB). Ningún número está estimado ni inventado.
> Donde algo es hipótesis y no hecho medido, está marcado como **HIPÓTESIS**.
>
> Script reproducible con los pasos corregidos: `src/parte_x_corregido.sql`.

## 1. Entorno medido

| Parámetro | Valor |
|---|---|
| Motor | MariaDB `10.6.23-MariaDB-0ubuntu0.22.04.1` (Ubuntu 22.04, WSL2) |
| RAM del guest | 2.911 MiB totales |
| `innodb_buffer_pool_size` (config) | **128 MiB** |
| `sort_buffer_size` | 2 MiB |
| `tmp_table_size` / `max_heap_table_size` | 16 MiB |
| `tmpdir` | `/tmp` |
| `reserva` antes de migrar | 6.000.000 filas, 583,3 MB, PK simple `(id_reserva)` |
| FK en `reserva` | `reserva_ibfk_1` → `habitacion`, `reserva_ibfk_2` → `huesped` |

Distribución real de `fecha_inicio` (medida con un escaneo completo, 12.236,8 ms):

| Año | Filas |
|---|---|
| 2023 | 2.187.132 |
| 2024 | 2.192.393 |
| 2025 | 1.620.475 |
| **Total** | **6.000.000** |

El rango se explica por `src/carga_masiva.py`: `fecha_base = 2023-01-01` y `dias_inicio` en 0..1000,
lo que da fechas entre 2023-01-01 y ~2025-09-27. Por eso alcanzan 3 particiones anuales.

## 2. Punto 49 — Estrategia de particionado

`PARTITION BY RANGE COLUMNS(fecha_inicio)` con 5 particiones:

| Partición | Límite | Filas reales |
|---|---|---|
| `p_historico` | `< '2023-01-01'` | 0 |
| `p_2023` | `< '2024-01-01'` | 2.187.132 |
| `p_2024` | `< '2025-01-01'` | 2.192.393 |
| `p_2025` | `< '2026-01-01'` | 1.620.475 |
| `p_futuro` | `< MAXVALUE` | 0 |

**Por qué `RANGE COLUMNS` y no `RANGE (TO_DAYS(...))`:** `RANGE COLUMNS` compara la columna `DATE`
directamente, sin expresión de partición. Evita toda la familia de problemas de funciones no
deterministas o no permitidas en la clave, y poda exactamente igual (verificado en el punto 51).
`YEAR(fecha_inicio)` no es necesario.

## 3. Hallazgo bloqueante: las FK impiden particionar

InnoDB/MariaDB **no puede particionar una tabla que tiene claves foráneas**. Verificado en una
base descartable antes de tocar `reserva`:

```sql
ALTER TABLE child PARTITION BY RANGE COLUMNS(fecha) (...);
-- ERROR 1217 (23000): Cannot delete or update a parent row: a foreign key constraint fails

-- la misma tabla SIN FK: funciona (p_2023, p_max creadas)
```

> Corrección: los apuntes previos citaban `ERROR 1503`. El error real en MariaDB 10.6.23 es **1217**.

Medida aplicada: soltar `reserva_ibfk_1` y `reserva_ibfk_2` (469 ms y 202 ms).

**Impacto real en este laboratorio: nulo.** `habitacion` y `huesped` tienen 0 filas mientras
`reserva` tiene 6M de filas que las referencian: la carga masiva corrió con
`SET FOREIGN_KEY_CHECKS = 0` (`src/carga_masiva.py` línea 22). Esas FK no estaban protegiendo
ninguna integridad que hoy exista. Los índices `id_habitacion` e `id_huesped` **se conservan**,
así que los JOIN siguen teniendo cobertura.

## 4. Hallazgo de sintaxis: `EXPLAIN PARTITIONS`

En MariaDB 10.6.23, el `EXPLAIN` común **no devuelve la columna `partitions`**:

```sql
EXPLAIN SELECT ... FROM reserva WHERE fecha_inicio >= ... ;
-- columnas: id, select_type, table, type, possible_keys, key, key_len, ref, rows, Extra
```

La forma que sí expone la poda es la sintaxis de 5.6:

```sql
EXPLAIN PARTITIONS SELECT ... FROM reserva WHERE ...;
-- columnas: ..., table, partitions, type, ...
```

> Corrección: los apuntes previos decían lo contrario. `EXPLAIN PARTITIONS` **sí** existe y
> funciona en MariaDB 10.6.23; es la única de las dos que muestra la partición usada.

`ANALYZE FORMAT=JSON` también funciona y aporta `r_total_time_ms`, `r_rows` y
`r_engine_stats.pages_read_count`, que es lo que se usó para medir de verdad.

## 5. Punto 50 — Migración de los 6.000.000 de registros

### 5.1 Lo que NO funciona (y por qué)

Se intentó el `ALTER TABLE ... PARTITION BY` monolítico. **Dos veces. Ninguna terminó.**

| Intento | Algoritmo | Resultado |
|---|---|---|
| 1 | por defecto (online / `LOCK=SHARED`) | 83 min en `copy to tmp table`, **2.870.107 row locks**, `0,00 writes/s`, `0,00 fsyncs/s` → hubo que matarlo |
| 2 | `ALGORITHM=COPY` explícito | 40 min, **2.899.107 row locks**, `trx_rows_modified = 0` → hubo que matarlo |

Contraste: el `ALTER TABLE reserva DROP PRIMARY KEY, ADD PRIMARY KEY (id_reserva, fecha_inicio)`
sobre las mismas 6M filas tardó **212 s**. Es decir, el volumen no es el problema.

Después se intentó migrar por lotes de 250.000 filas (24 lotes, cada uno su propia transacción,
así los locks se liberan en cada commit). **También degrada:**

| Lote | Duración |
|---|---|
| 1–3 | 57 s, 30 s, 25 s |
| 8 | 131 s |
| 9 | 188 s |
| 10 | 301 s |
| 11 | **27 min sin terminar** (cortado) |

> **HIPÓTESIS** (no medido de forma aislada): la causa es el `innodb_buffer_pool_size` de 128 MiB
> contra una tabla de 583 MB repartida en 5 archivos de partición con inserción en orden aleatorio
> por fecha: cada INSERT necesita leer páginas de destino al azar. La correlación es fuerte —
> la degradación empieza justo cuando el destino supera el tamaño del buffer pool, y los dos
> intentos de `ALTER` se estancan ambos cerca de los ~2,9M row locks. No se aisló la causa.

### 5.2 Lo que SÍ funcionó

```sql
-- 1) Buffer pool en runtime. Es DINÁMICO en MariaDB: no persiste y NO toca my.cnf.
SET GLOBAL innodb_buffer_pool_size = 2147483648;   -- 2048 MiB

-- 2) Tabla destino particionada y SIN índices secundarios
CREATE TABLE reserva_part (
  id_reserva      int(11) NOT NULL AUTO_INCREMENT,
  id_habitacion   int(11) NOT NULL,
  id_huesped      int(11) NOT NULL,
  fecha_inicio    date NOT NULL,
  fecha_fin       date NOT NULL,
  estado_reserva  varchar(30) DEFAULT 'Confirmada',
  PRIMARY KEY (id_reserva, fecha_inicio)
) ENGINE=InnoDB AUTO_INCREMENT=6000001
PARTITION BY RANGE COLUMNS(fecha_inicio) (
  PARTITION p_historico VALUES LESS THAN ('2023-01-01'),
  PARTITION p_2023      VALUES LESS THAN ('2024-01-01'),
  PARTITION p_2024      VALUES LESS THAN ('2025-01-01'),
  PARTITION p_2025      VALUES LESS THAN ('2026-01-01'),
  PARTITION p_futuro    VALUES LESS THAN (MAXVALUE)
);

-- 3) Migrar en 12 lotes de 500.000 (cada lote, su propia transacción)
INSERT INTO reserva_part SELECT * FROM reserva WHERE id_reserva BETWEEN <desde> AND <hasta>;

-- 4) Los índices secundarios se construyen DESPUÉS, en bloque
ALTER TABLE reserva_part
  ADD KEY id_habitacion (id_habitacion),
  ADD KEY id_huesped (id_huesped);

-- 5) Swap por metadatos, instantáneo
RENAME TABLE reserva TO reserva_old, reserva_part TO reserva;

-- 6) Volver el buffer pool al valor de la config
SET GLOBAL innodb_buffer_pool_size = 134217728;   -- 128 MiB
```

| Etapa | Tiempo medido |
|---|---|
| Migración de las 6M de filas (12 lotes de 500.000) | **150 s** |
| Construcción de los 2 índices secundarios | **78 s** |
| `ALTER` de PK (preparación, PK compuesta) | 212 s |

Detalle por lote (segundos): 53, 5, 4, 13, 3, 5, 16, 12, 5, 10, 7, 11.

> **Aclaración honesta:** se cambiaron **tres** cosas a la vez respecto del intento que degradaba
> (buffer pool 128 MiB → 2048 MiB, destino sin índices secundarios, lotes de 500.000 en vez de
> 250.000). **No se aisló cuál de las tres fue decisiva.** Lo medido es que las tres juntas
> llevan la migración de "no completa" a 150 s.

### 5.3 Integridad verificada

| Control | Resultado |
|---|---|
| Filas en `reserva` (origen) | 6.000.000 |
| Filas en `reserva_part` (destino) | 6.000.000 |
| Suma de las 5 particiones | 6.000.000 |
| `p_2023` | 2.187.132 (= distribución original) |
| `p_2024` | 2.192.393 (= distribución original) |
| `p_2025` | 1.620.475 (= distribución original) |
| `p_historico` / `p_futuro` | 0 / 0 |

La distribución por año quedó idéntica fila a fila. Migración sin pérdida.

## 6. Punto 51 — Comparación antes / después

Consulta de referencia (misma consulta, mismo resultado en ambas tablas: **1.281.853 filas**):

```sql
SELECT COUNT(*) FROM <tabla>
WHERE fecha_inicio >= '2023-06-01' AND fecha_inicio < '2024-01-01';
```

Comparación en igualdad de condiciones: **las dos tablas con `innodb_buffer_pool_size = 128 MiB`**,
en la misma sesión, alternando 3 rondas.

| Ronda | `reserva_old` (sin particionar) | `reserva` (particionada) |
|---|---|---|
| 1 | 4.139,7 ms | 1.152,9 ms |
| 2 | 4.235,0 ms | 2.351,6 ms |
| 3 | 6.331,8 ms | 1.296,5 ms |
| **Mediana** | **~4.235 ms** | **~1.297 ms** |

| Métrica | Antes | Después | Variación |
|---|---|---|---|
| `partitions` (EXPLAIN PARTITIONS) | `NULL` | **`p_2023`** | poda efectiva |
| `rows` (estimadas) | 5.979.957 | 2.179.893 | −63,6% |
| `r_rows` (filas realmente leídas) | 6.000.000 | 2.187.132 | **−63,5%** |
| `pages_accessed` | 8.796 – 10.192 | 2.517 – 2.540 | −72% |
| `pages_read_count` (lecturas de disco) | 769 – 1.802 | 256 – 269 | **−85% a −90%** |
| Tiempo (mediana) | ~4.235 ms | ~1.297 ms | **~3,3x más rápido** |

Consulta complementaria, rango 2023-01-01 .. 2023-06-01 (también poda a `p_2023`):

| Tabla | Tiempo | Filas leídas |
|---|---|---|
| `reserva_old` | 6.302,9 ms | 6.000.000 |
| `reserva` | 1.488,5 ms | 2.187.132 |

### Nota metodológica

La **primera** medición sobre la tabla particionada, tomada inmediatamente después de bajar el
buffer pool de 2048 a 128 MiB, dio **4.497,9 ms** — más lenta que la tabla sin particionar. Ese
valor es un **outlier** causado por el reajuste del buffer pool en curso. Con rondas alternadas
repetidas el resultado se estabiliza en ~1.297 ms. Se documenta el outlier a propósito: publicar
solo la medición que conviene sería deshonesto.

## 7. Conclusiones

1. **`RANGE COLUMNS(fecha_inicio)` con 5 particiones es la estrategia correcta** para este modelo
   (Punto 49). Los datos ocupan exactamente 3 de las 5 particiones.
2. **Las FK bloquean el particionado** (error 1217, verificado). En este laboratorio soltarlas no
   pierde integridad real porque las tablas referenciadas están vacías.
3. **El `ALTER TABLE ... PARTITION BY` monolítico no es viable** con 6M de filas y un buffer pool
   de 128 MiB: no completa. La migración por lotes sí.
4. **El `partition pruning` funciona y se midió** (Punto 51): una sola partición leída en vez de
   6M de filas, −63,5% de filas leídas, −85/90% de lecturas de disco y ~3,3x menos tiempo.
5. **El `innodb_buffer_pool_size` es dinámico** en MariaDB: se puede elevar para una operación
   puntual sin tocar `my.cnf` ni reiniciar, y volverlo atrás después.
6. **Para cargar una tabla particionada grande conviene** crear el destino sin índices
   secundarios, cargar por lotes, y construir los índices en bloque al final (78 s en este caso).

## 8. Estado del laboratorio al cerrar

- `reserva` → **particionada**, PK `(id_reserva, fecha_inicio)`, 6.000.000 filas, sin FK.
- `reserva_old` → se conserva la tabla original sin particionar (583 MB) **como punto de rollback**.
  Es descartable una vez validado el resultado.
- `innodb_buffer_pool_size` → devuelto a **128 MiB** (el valor de `my.cnf`).
- `habitacion`, `huesped`, `hotel`, `vista_mat_resumen_mensual` → intactas.
