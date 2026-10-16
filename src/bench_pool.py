#!/usr/bin/env python3
"""bench_pool.py — Costo de abrir conexiones vs. reutilizar vs. pool.

Compara 100 SELECT simples en 3 modos:
  a) abrir/cerrar una conexión por consulta (más costoso),
  b) una sola conexión reutilizada (base eficiente),
  c) MySQLConnectionPool(pool_size=5) (recomendado en apps multi-hilo).

No inventa tiempos: imprime los tiempos REALES medidos en esta corrida.
Pegar la tabla comparativa en el informe (punto de pool de conexiones).

Requisitos (comentario-requirements):
  pip install mysql-connector-python

Configuración por variables de entorno (valores por defecto entre paréntesis):
  DB_HOST (localhost), DB_PORT (3306), DB_USER (root),
  DB_PASSWORD (root), DB_NAME (hotel_db), BENCH_N (100).

Uso:
  python bench_pool.py
"""
import os
import statistics
import time

import mysql.connector
from mysql.connector import pooling

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "root"),
    "database": os.getenv("DB_NAME", "hotel_db"),
}
N = int(os.getenv("BENCH_N", "100"))

# Consulta simple y acotada: PK con LIMIT 1 (no trae 6M filas).
QUERY = "SELECT id_reserva, fecha_inicio FROM reserva ORDER BY id_reserva LIMIT 1"


def run_per_query(query, n):
    """Modo A: abre y cierra una conexión por cada consulta."""
    samples = []
    for _ in range(n):
        conn = mysql.connector.connect(**DB_CONFIG)
        try:
            cur = conn.cursor()
            t0 = time.perf_counter()
            cur.execute(query)
            cur.fetchall()
            samples.append((time.perf_counter() - t0) * 1000.0)
            cur.close()
        finally:
            conn.close()
    return samples


def run_single_conn(query, n):
    """Modo B: una sola conexión reutilizada para las N consultas."""
    samples = []
    conn = mysql.connector.connect(**DB_CONFIG)
    try:
        cur = conn.cursor()
        for _ in range(n):
            t0 = time.perf_counter()
            cur.execute(query)
            cur.fetchall()
            samples.append((time.perf_counter() - t0) * 1000.0)
        cur.close()
    finally:
        conn.close()
    return samples


def run_pool(query, n, pool_size=5):
    """Modo C: pool de conexiones (pool_size=5)."""
    pool = pooling.MySQLConnectionPool(
        pool_name="bench_pool", pool_size=pool_size, **DB_CONFIG
    )
    samples = []
    for _ in range(n):
        conn = pool.get_connection()
        try:
            cur = conn.cursor()
            t0 = time.perf_counter()
            cur.execute(query)
            cur.fetchall()
            samples.append((time.perf_counter() - t0) * 1000.0)
            cur.close()
        finally:
            conn.close()  # en pool, close() devuelve la conexión al pool
    return samples


def summarize(samples):
    return {
        "n": len(samples),
        "total_ms": sum(samples),
        "avg_ms": statistics.fmean(samples),
        "min_ms": min(samples),
        "max_ms": max(samples),
    }


def main():
    print(f"bench_pool: {N} SELECT simples por modo contra "
          f"{DB_CONFIG['user']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}")
    results = {}
    results["a) conexion por consulta"] = summarize(run_per_query(QUERY, N))
    results["b) conexion reutilizada"] = summarize(run_single_conn(QUERY, N))
    results["c) pool (size=5)"] = summarize(run_pool(QUERY, N, pool_size=5))

    print()
    print(f"{'modo':<28} {'total_ms':>10} {'prom_ms':>10} {'min_ms':>10} {'max_ms':>10}")
    print("-" * 72)
    for mode, s in results.items():
        print(f"{mode:<28} {s['total_ms']:>10.2f} {s['avg_ms']:>10.3f} "
              f"{s['min_ms']:>10.3f} {s['max_ms']:>10.3f}")
    print()
    base = results["b) conexion reutilizada"]["total_ms"]
    for mode, s in results.items():
        factor = s["total_ms"] / base if base else float("nan")
        print(f"{mode}: {s['total_ms']:.2f} ms total "
              f"({factor:.2f}x vs. conexion reutilizada)")
    print()
    print("[MEDIR] Pegar esta tabla en el informe; repetir con cache fria/caliente.")


if __name__ == "__main__":
    main()
