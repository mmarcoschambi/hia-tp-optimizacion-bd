# Parte V — Consultas complejas de negocio (Puntos 24 al 30)

Se agregaron consultas analíticas para trabajar sobre `hotel_db`, con foco en la tabla `reserva` de 6.000.000 de filas y sus tablas relacionadas. El script principal está en `src/parte_v_consultas_negocio.sql` y la validación estructural determinística está en `src/validate_parte_v_sql.py`.

## Supuestos de esquema

La carga masiva existente confirma el uso de `reserva(id_habitacion, id_huesped, fecha_inicio, fecha_fin, estado_reserva)`. Para resolver las consultas de negocio se usa el modelo hotelero normalizado esperado por el TP:

| Tabla | Columnas usadas | Motivo |
| --- | --- | --- |
| `reserva` | `id_reserva`, `id_habitacion`, `id_huesped`, `fecha_inicio`, `fecha_fin`, `estado_reserva` | Hecho central de reservas y estados. |
| `huesped` | `id_huesped`, `nombre`, `apellido`, `email` | Datos de cliente e historial. |
| `habitacion` | `id_habitacion`, `id_hotel`, `id_tipo_habitacion`, `numero_habitacion` | Puente entre reserva, hotel y tipo. |
| `tipo_habitacion` | `id_tipo_habitacion`, `nombre_tipo`, `precio_noche` | Cálculo de montos y agrupación por categoría. |
| `hotel` | `id_hotel`, `nombre_hotel`, `ciudad` | Análisis por establecimiento. |

Si la base local usa nombres distintos, la forma lógica de las consultas se conserva y solo hay que adaptar aliases/columnas.

## Índices recomendados

Para una tabla `reserva` de 6M filas, el cuello de botella principal es evitar recorridos completos cuando el filtro es selectivo y permitir joins por claves ya ordenadas.

```sql
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
```

No se fuerzan en el script para no modificar el entorno de evaluación: se documentan como estrategia de optimización.

## Resumen por punto

| Punto | Consulta | Decisión técnica | Por qué escala mejor |
| --- | --- | --- | --- |
| 24 | Reservas por rango de fechas y estado con conteo y montos. | Filtra por rango semiabierto (`>= desde` y `< hasta + 1 día`) y calcula monto con noches por precio. | El rango semiabierto evita problemas con tipos `DATETIME`; el índice por fecha/estado reduce filas antes de agregar. |
| 25 | Relación con huéspedes e historial. | Usa `INNER JOIN` para el huésped obligatorio y `LEFT JOIN` contra un CTE de historial previo. | El historial se agrega una vez por huésped, no fila por fila en la salida. |
| 26 | Ocupación por hotel y tipo de habitación. | Calcula solapamiento real de fechas con `LEAST`/`GREATEST`. | No pierde reservas que empiezan antes del período pero ocupan noches dentro del período. |
| 27 | Patrones de cancelación. | Usa `EXISTS` para verificar actividad confirmada/finalizada posterior. | `EXISTS` corta al primer match y se apoya en índice por huésped/fecha/estado. |
| 28 | Segmentación con `CASE WHEN`. | Agrega métricas por huésped y clasifica en una capa final. | Separar métricas y clasificación evita repetir expresiones complejas. |
| 29 | Agregaciones avanzadas. | Agrupa por hotel/tipo, aplica `HAVING` y ordena por ingresos estimados. | `HAVING` descarta grupos con poco soporte estadístico; el orden prioriza rendimiento de negocio. |
| 30 | Paginación eficiente. | Usa keyset pagination con `(fecha_inicio, id_reserva) > (?, ?)`. | Evita `OFFSET` alto, que lee y descarta filas crecientes a medida que avanza la página. |

## Comparativa: OFFSET alto vs keyset pagination

`LIMIT 100 OFFSET 5000000` parece simple, pero obliga al motor a ubicar, ordenar y descartar cinco millones de filas antes de devolver las 100 pedidas. En una tabla grande esto degrada linealmente con la profundidad de página.

La paginación keyset guarda la última clave visible de la página anterior (`fecha_inicio`, `id_reserva`) y pide la siguiente ventana:

```sql
WHERE (r.fecha_inicio, r.id_reserva) > (@ultima_fecha_inicio, @ultimo_id_reserva)
ORDER BY r.fecha_inicio, r.id_reserva
LIMIT @page_size;
```

Con el índice `idx_reserva_keyset(fecha_inicio, id_reserva)`, el motor continúa desde la posición ya conocida del árbol B+ en lugar de contar filas descartadas. Además, `id_reserva` funciona como desempate estable cuando muchas reservas comparten la misma fecha.

## Validación determinística

Se agregó `src/validate_parte_v_sql.py` para validar sin depender de una instancia local de MySQL/MariaDB. La validación comprueba:

- existencia de secciones `P24` a `P30`;
- presencia de constructos requeridos (`COUNT`, `SUM`, `INNER JOIN`, `LEFT JOIN`, `EXISTS`, `CASE WHEN`, `GROUP BY`, `HAVING`);
- uso de comparación tipo keyset en el punto 30;
- ausencia de `OFFSET` en el punto 30;
- paréntesis balanceados y cantidad mínima de sentencias.

Comando:

```bash
python src/validate_parte_v_sql.py
```

Resultado esperado:

```text
OK: Parte V SQL structure validated for P24-P30
OK: <n> SQL statements/comments blocks found
OK: validated file src/parte_v_consultas_negocio.sql
```
