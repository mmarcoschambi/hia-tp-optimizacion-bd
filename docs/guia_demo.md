# Demo TP HotelDB — Guía de uso (5 min, no técnica)

> Para vos, no para el Word. Sirve para mostrar en vivo sin trabarte.
> Base: `hotel_db`, MariaDB 10.6.23, tabla `reserva` 6M. Todo en minúsculas.

## 1. Qué vas a mostrar (orden)
1. **La base anda** (10 seg): versión + tamaño.
2. **El problema** (15 seg): consulta pesada tarda ~11s.
3. **La solución** (15 seg): tabla resumen tarda 0.001s.
4. **Pool** (20 seg): reutilizar conexiones es 4.8x más rápido.
5. **Cierre**: particionado queda en copia (no lo ejecutes en vivo).

## 2. Comandos exactos (copiá-pega en este orden)

```sql
-- A) Anda:
SELECT VERSION();
SELECT @@innodb_buffer_pool_size/1024/1024 AS pool_mib;
-- Decís: "10.6.23, pool 128 MB, 6 millones de reservas"

-- B) Problema (tarda ~11s, avisá antes):
ANALYZE SELECT COUNT(*) FROM reserva
WHERE fecha_inicio >= '2023-06-01' AND fecha_inicio < '2024-01-01';
-- Decís: "lee 6M, full scan, 11 segundos"

-- C) Solución (instantáneo):
ANALYZE SELECT * FROM vista_mat_resumen_mensual WHERE anio=2023 ORDER BY mes;
-- Decís: "12 meses precalculados, 1 milisegundo"

-- D) Lenta de 8s (si te piden slow log):
SELECT COUNT(*), SUM(DATEDIFF(fecha_fin, fecha_inicio))
FROM reserva WHERE estado_reserva='Finalizada';
-- Decís: "3.9M filas, 8 segundos, supera el umbral de 2s"
```

En otra terminal (PowerShell/WSL):
```bash
python3 bench_pool.py
# Decís: "abrir conexión cada vez: 96ms, reutilizar: 20ms"
```

## 3. Qué decir si preguntan
- **¿Por qué tarda?** "Sin índice por fecha, lee todo. Con resumen lee 12 filas."
- **¿Slow log vacío?** "El servidor no vuelca a tabla ni archivo, dejo constancia con tiempo > umbral."
- **¿Particiones?** "Queda en copia `Reserva_part`, el ALTER sobre 6M bloquea varios minutos, no lo corro en vivo."
- **¿Mayúsculas?** "En Linux es `reserva` minúscula, con mayúscula da error 1146."

## 4. No hagas en vivo
- ❌ `ALTER ... PARTITION` (bloquea minutos)
- ❌ `INSERT INTO Reserva_part SELECT *` (minutos)
- ❌ `OPTIMIZE TABLE reserva` (bloquea)
- ❌ `COUNT(*) FROM reserva` sin filtro (supera 60s, error 1969)

Con A+B+C+D + pool ya demostrás todo. 3 min total.
