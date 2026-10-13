"""Bounded repeated payload SELECTs on the authorized disposable hotel_db lab.

Use --run --case Q1..Q8. First pair warms shared caches; subsequent pairs
alternate order. No OS/buffer-pool flush: 'warm' is not a controlled cold run.
Incomplete executions (server/client deadline) never count as latencies.
"""
import argparse
import hashlib
import json
import os
import time

import mysql.connector

from run_parte_vi_vii_lab import QUERIES


class Deadline(Exception):
    pass


def connect():
    return mysql.connector.connect(
        host="127.0.0.1", port=3306, user="root", password=os.getenv("DB_PASSWORD", "root"),
        database="hotel_db", connection_timeout=5, read_timeout=35, autocommit=True,
    )


def sample(sql, page=False):
    conn = connect()
    started = time.monotonic()
    rows = 0
    digest = hashlib.sha256()
    multiset_sum = 0
    bytes_estimate = 0
    try:
        control = conn.cursor()
        control.execute("SET SESSION max_statement_time=20")
        control.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT")
        if page:
            control.execute("SELECT fecha_inicio,id_reserva FROM reserva FORCE INDEX(idx_pvii_keyset) "
                            "ORDER BY fecha_inicio,id_reserva LIMIT 999,1")
            date, ident = control.fetchone()
            sql = sql.format(date=date.isoformat(), ident=int(ident))
        control.close()
        cursor = conn.cursor(buffered=False)
        started = time.monotonic()
        cursor.execute(sql)
        while True:
            batch = cursor.fetchmany(512)
            if not batch:
                break
            for row in batch:
                encoded = json.dumps(row, default=str, separators=(",", ":")).encode()
                digest.update(len(encoded).to_bytes(4, "big"))
                digest.update(encoded)
                multiset_sum = (multiset_sum + int.from_bytes(hashlib.sha256(encoded).digest(), "big")) % (1 << 256)
                bytes_estimate += len(encoded)
                rows += 1
            if time.monotonic() - started > 30:
                raise Deadline("client deadline exceeded; partial result discarded")
        cursor.close()
        conn.rollback()
        return {"status": "complete", "seconds": round(time.monotonic() - started, 3),
                "rows": rows, "sha256": digest.hexdigest(),
                "multiset_sha256": f"{multiset_sum:064x}", "approx_json_bytes": bytes_estimate}
    except (mysql.connector.Error, Deadline) as exc:
        return {"status": "incomplete", "seconds_until_abort": round(time.monotonic() - started, 3),
                "rows_before_abort": rows, "reason": str(exc)[:130]}
    finally:
        conn.close()  # closes open snapshot, including when a streaming query is aborted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="confirm disposable lab")
    parser.add_argument("--case", choices=[f"Q{i}" for i in range(1, 9)], required=True)
    parser.add_argument("--repeat", type=int, default=3)
    args = parser.parse_args()
    if not args.run or not 1 <= args.repeat <= 5:
        parser.error("--run and 1..5 repeats required")
    probe = connect()
    try:
        cur = probe.cursor()
        cur.execute("SELECT @@version, @@query_cache_type, @@innodb_buffer_pool_size")
        version, query_cache_type, buffer_size = cur.fetchone()
        cur.execute("SHOW TABLE STATUS LIKE 'reserva'")
        table_status = cur.fetchall()
        if probe.database != "hotel_db" or len(table_status) != 1 or table_status[0][1] != "InnoDB":
            raise RuntimeError("Unexpected lab database/engine")
        cur.execute("SHOW INDEX FROM reserva")
        keys = {row[2] for row in cur.fetchall()}
        cur.close()
    finally:
        probe.close()
    if args.case == "Q8" and "idx_pvii_keyset" not in keys:
        raise RuntimeError("Q8 needs idx_pvii_keyset; cursor sort would be unbounded")
    if args.case == "Q8":
        original = "SELECT id_reserva,fecha_inicio FROM reserva ORDER BY fecha_inicio,id_reserva LIMIT 20 OFFSET 1000"
        optimized = ("SELECT id_reserva,fecha_inicio FROM reserva WHERE fecha_inicio > '{date}' "
                     "OR (fecha_inicio = '{date}' AND id_reserva > {ident}) "
                     "ORDER BY fecha_inicio,id_reserva LIMIT 20")
    else:
        original, optimized = QUERIES[args.case]
    statements = {"original": original, "alternative": optimized}
    report = {"case": args.case, "server": version, "query_cache_type": query_cache_type,
              "buffer_pool_bytes": buffer_size, "keys": sorted(keys), "statement_cap_seconds": 20,
              "client_cap_seconds": 30, "same_sql": original == optimized,
              "samples": [], "warmup": {}}
    for label, sql in statements.items():
        report["warmup"][label] = sample(sql, page=(args.case == "Q8" and label == "alternative"))
    for round_id in range(args.repeat):
        order = ("original", "alternative") if round_id % 2 == 0 else ("alternative", "original")
        for label in order:
            report["samples"].append({"round": round_id + 1, "variant": label,
                **sample(statements[label], page=(args.case == "Q8" and label == "alternative"))})
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
