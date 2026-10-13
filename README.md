# Trabajo Práctico: Diseño y Optimización de Bases de Datos Avanzado

Cátedra: Herramientas Informáticas Avanzadas (HIA)  
Carrera: Analista Programador Universitario (APU) — Facultad de Ingeniería

---

## 1. Requisitos y Entorno

- **Motor de Base de Datos:** MySQL 8.0+ o MariaDB 10.6+ (InnoDB).
- **Puerto:** `3306` (por defecto).
- **Base de Datos:** `hotel_db`.
- **Python:** 3.10 o superior.
- **Librerías Python:**
  ```bash
  pip install mysql-connector-python
  ```

---

## 2. Puesta en Marcha: Levantar y Poblar la Base de Datos

Para que cualquier integrante del equipo reproduzca exactamente el mismo entorno de datos y mediciones:

### Paso 1: Configurar la conexión
Verificar los parámetros de conexión local en [`src/carga_masiva.py`](src/carga_masiva.py) y en los scripts de ejecución (`host`, `port`, `user`, `password`, `database`). Por defecto están configurados para `root:root` en `localhost:3306`.

### Paso 2: Carga masiva de datos (6.000.000 de registros)
Ejecutar el script de inserción masiva en lotes para generar el volumen de prueba de la tabla `reserva`:
```bash
python src/carga_masiva.py
```
*Nota: El script desactiva temporalmente las restricciones de claves foráneas y controla los commits en lotes para optimizar los tiempos de carga en disco.*

### Paso 3: Benchmark Cold vs. Warm Cache (Punto 23)
Medir el comportamiento de lectura en disco vs. lectura en InnoDB Buffer Pool:
```bash
python src/test_cache.py
```
*Resultados documentados en [`docs/benchmark_cache_punto_23.md`](docs/benchmark_cache_punto_23.md).*

---

## 3. Consultas y Validaciones Implementadas

### Parte V: Consultas Complejas de Negocio (Puntos 24 al 30)
- **Script SQL:** [`src/parte_v_consultas_negocio.sql`](src/parte_v_consultas_negocio.sql)
- **Documentación teórica y justificaciones:** [`docs/parte_v_consultas_negocio.md`](docs/parte_v_consultas_negocio.md)
- **Validador sintáctico y estructural:**
  ```bash
  python src/validate_parte_v_sql.py
  ```

### Parte VI y VII: Planes de Ejecución EXPLAIN y Optimización de Índices (Puntos 31 al 39)
- **Script SQL:** [`src/parte_vi_vii_experimentos.sql`](src/parte_vi_vii_experimentos.sql)
- **Documentación y mediciones:** [`docs/parte_vi_explain_indices.md`](docs/parte_vi_explain_indices.md)
- **Validador estructural:**
  ```bash
  python src/validate_parte_vi_vii.py
  ```
- **Laboratorio de planes y mediciones:**
  ```bash
  python src/run_parte_vi_vii_lab.py
  python src/run_parte_vi_vii_payload.py
  ```

### Parte VIII: Concurrencia, Transacciones y Bloqueos (Puntos 40 al 42)
- **Scripts de sesiones:** [`src/parte_viii_session_a.sql`](src/parte_viii_session_a.sql) y [`src/parte_viii_session_b.sql`](src/parte_viii_session_b.sql)
- **Documentación:** [`docs/parte_viii_bloqueos.md`](docs/parte_viii_bloqueos.md)
- **Validador y ejecución del laboratorio de bloqueos:**
  ```bash
  python src/validate_parte_viii.py
  python src/run_parte_viii_lab.py
  ```

---

## 4. Estado de Avance y Puntos Pendientes

| Sección | Puntos | Estado | Responsable / Ubicación |
|---|---|---|---|
| Parte I a IV | 1 al 23 | Completado | Documentado en `docs/HIA-BDOPTIMIZACION.docx` y scripts base |
| Parte V | 24 al 30 | Completado | `src/parte_v_consultas_negocio.sql` y `docs/parte_v_consultas_negocio.md` |
| Parte VI y VII | 31 al 39 | Completado | `src/parte_vi_vii_experimentos.sql` y `docs/parte_vi_explain_indices.md` |
| Parte VIII | 40 al 42 | Completado | `src/run_parte_viii_lab.py` y `docs/parte_viii_bloqueos.md` |
| **Parte IX** | **43 al 48** | **Pendiente** | Configuración de servidor, InnoDB Buffer Pool, memoria y CPU/disco |
| **Parte X** | **49 al 52** | **Pendiente** | Particionamiento (`PARTITION BY`), pruning y vistas materializadas |

---

## 5. Próximos Pasos para la Entrega Final

1. **Desarrollar Partes IX y X:** Abordar los puntos 43 al 52 de la consigna.
2. **Consolidar el Informe:** Traspasar las secciones redactadas en la carpeta `docs/` al documento formal [`docs/HIA-BDOPTIMIZACION.docx`](docs/HIA-BDOPTIMIZACION.docx).
3. **Exportar a PDF:** Generar el PDF final para la presentación formal antes de la fecha límite (15-10-2026).
