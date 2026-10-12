# Proposal: feat(benchmark): punto 23 benchmark de cache frio vs caliente sobre 6M filas

## Intent
### Objetivo
Ejecutar y documentar el Punto 23 del Trabajo Practico de Optimizacion de BD.

### Enfoque Didactico (Matt Teach / Arquitectura de BD)
- No quedarse solo con numeros frios: explicar el *por que* mecanico (paginas leidas de disco vs InnoDB Buffer Pool en RAM).
- Comprender el ciclo de vida de los datos y como el motor gestiona bloques (LRU) antes de escribir conclusiones.

### Tareas
- [ ] Ejecutar prueba de rendimiento Cold Cache vs Warm Cache con src/test_cache.py sobre la tabla reserva (6.000.000 registros).
- [ ] Documentar tiempos, speedup y explicacion conceptual del InnoDB Buffer Pool.
- [ ] Extraer y documentar el plan de ejecucion EXPLAIN FORMAT=JSON de la consulta.

## Context
URL: https://github.com/mmarcoschambi/hia-tp-optimizacion-bd/issues/1
Labels:
