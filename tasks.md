# Tasks: feat(benchmark): punto 23 benchmark de cache frio vs caliente sobre 6M filas

### Objetivo
Ejecutar y documentar el Punto 23 del Trabajo Practico de Optimizacion de BD.

### Enfoque Didactico (Matt Teach / Arquitectura de BD)
- No quedarse solo con numeros frios: explicar el *por que* mecanico (paginas leidas de disco vs InnoDB Buffer Pool en RAM).
- Comprender el ciclo de vida de los datos y como el motor gestiona bloques (LRU) antes de escribir conclusiones.

### Tareas
- [x] Ejecutar prueba de rendimiento Cold Cache vs Warm Cache con src/test_cache.py sobre la tabla reserva (6.000.000 registros).
  - Evidencia: tabla `reserva` verificada con 6.000.000 filas; corrida 1 = 15,4395 s; corrida 2 = 11,0120 s; corrida 3 = 10,0301 s.
- [x] Documentar tiempos, speedup y explicacion conceptual del InnoDB Buffer Pool.
  - Evidencia: `docs/HIA-BDOPTIMIZACION.docx` seccion 23 y `docs/benchmark_cache_punto_23.md`; speedup promedio contra cache caliente = 1,47x.
- [x] Extraer y documentar el plan de ejecucion EXPLAIN FORMAT=JSON de la consulta.
  - Evidencia: `access_type: ALL`, `rows: 5740499`, `filesort` y tabla temporal documentados en los artefactos.

URL: https://github.com/mmarcoschambi/hia-tp-optimizacion-bd/issues/1
Labels:
