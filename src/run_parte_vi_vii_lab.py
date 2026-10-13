"""Bounded optimizer measurements on explicitly authorized localhost lab only.

Modes: baseline, add-index (one owned index), indexed. JSON output contains
observations, including timeouts; no query returns millions of rows to Python.
"""
import argparse
import json
import os
import time

import mysql.connector

INDEXES = {
    "idx_pvii_guest_date": "(id_huesped, fecha_inicio)",
    "idx_pvii_date_guest": "(fecha_inicio, id_huesped)",
    "idx_pvii_state_date": "(estado_reserva, fecha_inicio)",
    "idx_pvii_keyset": "(fecha_inicio, id_reserva)",
}
QUERIES = {
    "Q1": ("SELECT id_reserva FROM reserva WHERE YEAR(fecha_inicio)=2024",
           "SELECT id_reserva FROM reserva WHERE fecha_inicio >= '2024-01-01' AND fecha_inicio < '2025-01-01'"),
    "Q2": ("SELECT id_reserva FROM reserva WHERE DATE(fecha_inicio)='2024-03-01'",
           "SELECT id_reserva FROM reserva WHERE fecha_inicio >= '2024-03-01' AND fecha_inicio < '2024-03-02'"),
    "Q3": ("SELECT id_reserva FROM reserva WHERE id_huesped + 0 = 42",
           "SELECT id_reserva FROM reserva WHERE id_huesped = 42"),
    "Q4": ("SELECT id_reserva FROM reserva WHERE id_huesped = 42 AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2025-01-01'",) * 2,
    "Q5": ("SELECT id_reserva FROM reserva WHERE estado_reserva = 'Cancelada' AND fecha_inicio >= '2024-01-01' AND fecha_inicio < '2024-02-01'",) * 2,
    "Q6": ("SELECT r.id_reserva FROM reserva AS r JOIN habitacion AS ha ON ha.id_habitacion + 0 = r.id_habitacion WHERE r.id_huesped = 42",
           "SELECT r.id_reserva FROM reserva AS r JOIN habitacion AS ha ON ha.id_habitacion = r.id_habitacion WHERE r.id_huesped = 42"),
    "Q7": ("SELECT * FROM reserva WHERE id_huesped = 42",
           "SELECT id_reserva, fecha_inicio FROM reserva WHERE id_huesped = 42"),
}


def connect():
    return mysql.connector.connect(
        host="127.0.0.1", port=3306, user="root", password=os.getenv("DB_PASSWORD", "root"),
        database="hotel_db", connection_timeout=5, read_timeout=900, autocommit=True,
    )


def plan(cursor, sql):
    cursor.execute("EXPLAIN FORMAT=JSON " + sql)
    tree = json.loads(cursor.fetchone()[0])["query_block"]
    tables = []

    def visit(node):
        if isinstance(node, dict):
            if "table_name" in node and "access_type" in node:
                tables.append({key: node.get(key) for key in ("table_name", "access_type", "key", "used_key_parts", "rows", "filtered")})
            for child in node.values():
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)

    visit(tree)
    return {"tables": tables, "query_cost": tree.get("cost_info", {}).get("query_cost")}


def measure(cursor, sql, payload=False):
    # COUNT(*) tests full qualifying set, but has a DIFFERENT plan from payload SELECT.
    # Q7 is bounded by guest equality and tests transported projection instead.
    measured_sql = sql if payload else "SELECT COUNT(*) FROM (" + sql + ") AS measured"
    started = time.monotonic()
    try:
        cursor.execute(measured_sql)
        if payload:
            rows = cursor.fetchall()
            return {"seconds": round(time.monotonic() - started, 3), "rows": len(rows),
                    "approx_json_bytes": sum(len(json.dumps(r, default=str)) for r in rows),
                    "metric": "payload"}
        return {"seconds": round(time.monotonic() - started, 3),
                "rows": cursor.fetchone()[0], "metric": "count_variant"}
    except mysql.connector.Error as exc:
        return {"seconds": round(time.monotonic() - started, 3), "error_code": exc.errno,
                "error": exc.msg[:120], "metric": "payload" if payload else "count_variant"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="confirm lab is disposable")
    parser.add_argument("--stage", choices=("baseline", "add-index", "indexed", "write-probe", "join-fixture", "cleanup"), required=True)
    parser.add_argument("--index", choices=tuple(INDEXES))
    args = parser.parse_args()
    if not args.run or (args.stage in ("add-index", "cleanup")) != bool(args.index):
        parser.error("--run required, and --index required only for add-index or cleanup")
    conn = connect()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT @@version, @@hostname, @@autocommit")
        version, host, autocommit = cursor.fetchone()
        cursor.execute("SHOW TABLE STATUS LIKE 'reserva'")
        metadata = cursor.fetchone()
        if conn.database != "hotel_db" or metadata[1] != "InnoDB":
            raise RuntimeError("Unexpected database or engine")
        cursor.execute("SHOW INDEX FROM reserva")
        keys = sorted(set(row[2] for row in cursor.fetchall()))
        report = {"version": version, "host": host, "stage": args.stage, "keys": keys,
                  "autocommit": autocommit, "table_rows_estimate": metadata[4],
                  "index_length_bytes": metadata[8]}
        if args.stage == "add-index":
            if args.index in keys:
                raise RuntimeError("Index already exists; refusing to claim creation")
            start = time.monotonic()
            cursor.execute(f"CREATE INDEX {args.index} ON reserva {INDEXES[args.index]}")
            report["created_index"] = args.index
            report["build_seconds"] = round(time.monotonic() - start, 3)
            cursor.execute("ANALYZE TABLE reserva")
            report["analyze_result"] = cursor.fetchall()
        elif args.stage == "cleanup":
            if args.index not in keys:
                raise RuntimeError("Expected owned index is absent")
            cursor.execute(f"DROP INDEX {args.index} ON reserva")
            report["dropped_index"] = args.index
        elif args.stage == "join-fixture":
            cursor.execute("SELECT COUNT(*) FROM habitacion")
            if cursor.fetchone()[0] != 0:
                raise RuntimeError("This fixture is only valid when habitacion is empty")
            cursor.execute("CREATE TEMPORARY TABLE tp_habitacion (id_habitacion INT PRIMARY KEY) ENGINE=InnoDB")
            try:
                cursor.execute("INSERT INTO tp_habitacion SELECT DISTINCT id_habitacion FROM reserva WHERE id_huesped=42")
                report["fixture_rooms"] = cursor.rowcount
                report["join"] = {}
                for label, condition in (("expression", "ha.id_habitacion + 0 = r.id_habitacion"),
                                         ("direct", "ha.id_habitacion = r.id_habitacion")):
                    sql = ("SELECT r.id_reserva FROM reserva r JOIN tp_habitacion ha ON " + condition
                           + " WHERE r.id_huesped=42")
                    cursor.execute("EXPLAIN FORMAT=JSON " + sql)
                    tree = json.loads(cursor.fetchone()[0])
                    start = time.monotonic()
                    cursor.execute(sql)
                    report["join"][label] = {"rows": len(cursor.fetchall()),
                        "seconds": round(time.monotonic() - start, 4), "json_tree": tree}
            finally:
                cursor.execute("DROP TEMPORARY TABLE tp_habitacion")
        elif args.stage == "write-probe":
            cursor.execute("SELECT estado_reserva,fecha_inicio FROM reserva WHERE id_reserva=1")
            original = cursor.fetchone()
            if original is None:
                raise RuntimeError("Probe row absent")
            samples = []
            for _ in range(7):
                cursor.execute("START TRANSACTION")
                try:
                    start = time.monotonic()
                    cursor.execute("UPDATE reserva SET estado_reserva=%s, fecha_inicio=DATE_ADD(fecha_inicio, INTERVAL 1 DAY) WHERE id_reserva=1",
                                   ("Confirmada" if original[0] != "Confirmada" else "Cancelada",))
                    samples.append(round(1000 * (time.monotonic() - start), 3))
                finally:
                    conn.rollback()
            cursor.execute("SELECT estado_reserva,fecha_inicio FROM reserva WHERE id_reserva=1")
            report["value_unchanged"] = cursor.fetchone() == original
            report["update_rollback_ms"] = samples
        else:
            cursor.execute("SET SESSION max_statement_time = 12")
            report["plans"] = {}
            for name, (original, optimized) in QUERIES.items():
                report["plans"][name] = {}
                for label, sql in (("original", original), ("optimized", optimized)):
                    report["plans"][name][label] = {"plan": plan(cursor, sql),
                        "measurement": measure(cursor, sql, payload=(name == "Q7"))}
            # Same snapshot for both pages; with date index, cursor retrieval is bounded.
            if "idx_pvii_keyset" in keys:
                cursor.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT")
                try:
                    cursor.execute("SET SESSION max_statement_time = 12")
                    cursor.execute("SELECT fecha_inicio,id_reserva FROM reserva ORDER BY fecha_inicio,id_reserva LIMIT 999,1")
                    date, ident = cursor.fetchone()
                    queries = (
                        "SELECT id_reserva,fecha_inicio FROM reserva ORDER BY fecha_inicio,id_reserva LIMIT 20 OFFSET 1000",
                        "SELECT id_reserva,fecha_inicio FROM reserva WHERE fecha_inicio > "
                        f"'{date.isoformat()}' OR (fecha_inicio = '{date.isoformat()}' AND id_reserva > {int(ident)}) "
                        "ORDER BY fecha_inicio,id_reserva LIMIT 20",
                    )
                    report["plans"]["Q8"] = {}
                    pages = []
                    for label, sql in zip(("original", "optimized"), queries):
                        t0 = time.monotonic()
                        p = plan(cursor, sql)
                        cursor.execute(sql)
                        rows = cursor.fetchall()
                        pages.append(rows)
                        report["plans"]["Q8"][label] = {"plan": p, "measurement": {
                            "seconds": round(time.monotonic()-t0, 3), "rows": len(rows), "metric": "page"}}
                    report["q8_same_page"] = pages[0] == pages[1]
                except mysql.connector.Error as exc:
                    report["plans"]["Q8"] = {"error_code": exc.errno, "error": exc.msg[:120]}
                finally:
                    conn.rollback()
            else:
                report["plans"]["Q8"] = {"skipped": "requires (fecha_inicio,id_reserva) keyset index for ordered cursor"}
        print(json.dumps(report, default=str, ensure_ascii=False, indent=2), flush=True)
        cursor.close()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
