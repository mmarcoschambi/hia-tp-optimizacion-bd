import time
import mysql.connector

conn = mysql.connector.connect(
    host="localhost",
    port=3306,
    user="root",
    password="root",
    database="hotel_db"
)
cursor = conn.cursor()

query = """
SELECT estado_reserva, COUNT(*) AS total
FROM reserva
WHERE fecha_inicio BETWEEN '2023-06-01' AND '2023-12-31'
GROUP BY estado_reserva;
"""

print("=== EXPERIMENTO PUNTO 23: COLD CACHE vs WARM CACHE ===")

# Corrida 1
t0 = time.perf_counter()
cursor.execute(query)
res1 = cursor.fetchall()
t1 = time.perf_counter()
duracion_run1 = t1 - t0
print(f"Corrida 1 (Cold Cache): {duracion_run1:.4f} segundos")
for r in res1:
    print(f"  - {r[0]}: {r[1]:,}")

# Corrida 2
t2 = time.perf_counter()
cursor.execute(query)
res2 = cursor.fetchall()
t3 = time.perf_counter()
duracion_run2 = t3 - t2
print(f"\nCorrida 2 (Warm Cache): {duracion_run2:.4f} segundos")

# Corrida 3
t4 = time.perf_counter()
cursor.execute(query)
res3 = cursor.fetchall()
t5 = time.perf_counter()
duracion_run3 = t5 - t4
print(f"Corrida 3 (Warm Cache): {duracion_run3:.4f} segundos")

speedup = duracion_run1 / duracion_run2 if duracion_run2 > 0 else 0
print(f"\n-> Aceleración (Speedup): {speedup:.2f}x más rápido en memoria.")

cursor.close()
conn.close()
