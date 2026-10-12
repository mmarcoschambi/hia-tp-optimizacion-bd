# Tasks: feat(queries): parte V consultas complejas de negocio puntos 24 al 30

### Objetivo
Disenar, optimizar y documentar las consultas complejas de la Parte V (Puntos 24 al 30).

### Tareas
- [x] Punto 24: Consulta de reservas por rango de fechas y estado con conteo y montos.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P24; validado por `src/validate_parte_v_sql.py`.
- [x] Punto 25: Relacion con huespedes e historial usando INNER JOIN y LEFT JOIN.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P25; documentado en `docs/parte_v_consultas_negocio.md`.
- [x] Punto 26: Analisis de ocupacion por hotel y tipo de habitacion.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P26 con cálculo de solapamiento de fechas.
- [x] Punto 27: Deteccion de patrones de cancelacion con subconsultas / EXISTS.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P27 con `EXISTS` y `HAVING`.
- [x] Punto 28: Segmentacion de clientes y clasificacion condicional con CASE WHEN.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P28 con CTE de métricas y `CASE WHEN`.
- [x] Punto 29: Agregaciones avanzadas con GROUP BY, HAVING y ordenamiento por rendimiento.
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P29 con KPIs hotel/tipo.
- [x] Punto 30: Estrategia de paginacion eficiente sobre grandes volumenes (evitar OFFSET alto).
  - Evidencia: `src/parte_v_consultas_negocio.sql` sección P30 con keyset pagination y sin `OFFSET`.
- [x] Documentacion conceptual, comparativas y justificaciones.
  - Evidencia: `docs/parte_v_consultas_negocio.md`.
- [x] Validaciones sintacticas/deterministicas.
  - Evidencia: `python src/validate_parte_v_sql.py` ejecutado correctamente.

URL: https://github.com/mmarcoschambi/hia-tp-optimizacion-bd/issues/2
Labels:
