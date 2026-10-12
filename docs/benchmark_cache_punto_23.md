# Punto 23 — Benchmark de caché frío vs. caché caliente

## Objetivo

Medir el impacto del caché de InnoDB sobre una consulta agregada ejecutada contra la tabla `reserva` con 6.000.000 de registros.

Consulta evaluada:

```sql
SELECT estado_reserva, COUNT(*) AS total
FROM reserva
WHERE fecha_inicio BETWEEN '2023-06-01' AND '2023-12-31'
GROUP BY estado_reserva;
```

## Datos verificados

- Tabla evaluada: `reserva`.
- Volumen verificado: `6.000.000` filas.
- Script ejecutado: `src/test_cache.py`.
- Motor esperado del TP: MySQL/MariaDB con InnoDB.

## Resultados del benchmark

| Corrida | Condición observada | Tiempo |
| --- | --- | ---: |
| 1 | Primera ejecución / caché frío relativo | 15,4395 s |
| 2 | Caché caliente | 11,0120 s |
| 3 | Caché caliente | 10,0301 s |

Resultados devueltos por la consulta:

| estado_reserva | Total |
| --- | ---: |
| Cancelada | 191.979 |
| Confirmada | 255.964 |
| Finalizada | 833.910 |

Métricas derivadas:

- Speedup informado por el script, comparando corrida 1 contra corrida 2: `1,40x`.
- Speedup contra la corrida 3: `1,54x`.
- Promedio de corridas calientes: `(11,0120 + 10,0301) / 2 = 10,52105 s`.
- Speedup contra promedio caliente: `15,4395 / 10,52105 = 1,47x`.

## Plan de ejecución

`EXPLAIN FORMAT=JSON`:

```json
{
  "query_block": {
    "select_id": 1,
    "filesort": {
      "sort_key": "reserva.estado_reserva",
      "temporary_table": {
        "table": {
          "table_name": "reserva",
          "access_type": "ALL",
          "rows": 5740499,
          "filtered": 100,
          "attached_condition": "reserva.fecha_inicio between <cache>('2023-06-01') and <cache>('2023-12-31')"
        }
      }
    }
  }
}
```

Lectura técnica del plan:

- `access_type: "ALL"` indica un recorrido completo de la tabla `reserva`.
- El optimizador estima leer aproximadamente `5.740.499` filas.
- La condición por `fecha_inicio` se aplica durante el escaneo.
- El `GROUP BY estado_reserva` requiere una tabla temporal y `filesort` para agrupar los estados.
- Este plan es coherente con una consulta analítica de baja selectividad sobre millones de filas: el costo principal no está en ubicar una fila puntual, sino en leer muchas páginas de datos y agregarlas.

## Explicación mecánica: por qué mejora el caché caliente

InnoDB no trabaja fila por fila desde el disco para cada acceso lógico. Lee páginas de datos —típicamente bloques de 16 KB— y las coloca en el InnoDB Buffer Pool, que es la memoria caché principal del motor para datos e índices.

En la primera corrida, una parte importante de las páginas necesarias para recorrer `reserva` todavía no está en RAM. Por eso el motor debe resolver más lecturas físicas desde disco/SSD hacia memoria. Esa ruta es más lenta porque involucra I/O del sistema operativo, espera del dispositivo de almacenamiento y transferencia de bloques completos.

En las corridas siguientes, muchas de esas mismas páginas ya quedaron cargadas en el Buffer Pool. La consulta sigue haciendo un escaneo grande, pero ahora una fracción mayor de las lecturas se resuelve como lecturas lógicas en memoria. Por eso baja el tiempo desde `15,4395 s` hasta alrededor de `10–11 s`.

La mejora no vuelve instantánea la consulta porque el plan sigue siendo un full table scan con agregación: aunque las páginas estén calientes, MySQL todavía debe recorrer millones de registros, evaluar el rango de fechas, contar por `estado_reserva` y agrupar. El Buffer Pool reduce el costo de I/O, pero no elimina el costo de CPU ni el costo algorítmico de procesar una porción grande de la tabla.

InnoDB administra el Buffer Pool con una política cercana a LRU: conserva páginas usadas recientemente y desplaza páginas menos útiles cuando necesita espacio. En este caso, ejecutar repetidamente la misma consulta favorece que las páginas de `reserva` y estructuras auxiliares permanezcan residentes, generando el efecto de caché caliente observado.

## Nota metodológica

El script mide una primera corrida seguida de corridas posteriores. Eso permite observar el efecto práctico de calentamiento del Buffer Pool. Para un experimento de caché frío estricto habría que controlar explícitamente el estado del servidor —por ejemplo reiniciando MySQL/MariaDB o limpiando el Buffer Pool—, operación que no se automatizó para evitar efectos destructivos o dependientes del entorno local.
