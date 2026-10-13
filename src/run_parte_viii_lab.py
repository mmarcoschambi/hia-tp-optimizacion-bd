"""Bounded, two-connection InnoDB lock experiment on the authorized TP lab.

Run explicitly with --run after confirming localhost:3306/hotel_db is disposable.
Never sources the manual snippets or leaves an open transaction intentionally.
"""
import argparse
import json
import os
import threading
import time

import mysql.connector


def connect():
    return mysql.connector.connect(
        host="127.0.0.1", port=3306, user="root",
        password=os.getenv("DB_PASSWORD", "root"), database="hotel_db",
        connection_timeout=5, read_timeout=12, write_timeout=12,
        autocommit=True,
    )


def one_wait(b, sql, id_value):
    started = threading.Event()
    result = {}

    def work():
        try:
            cursor = b.cursor()
            started.set()
            t0 = time.monotonic()
            cursor.execute(sql, (id_value,))
            if cursor.with_rows:
                cursor.fetchall()
            result.update(seconds=round(time.monotonic() - t0, 3), status="completed")
            cursor.close()
        except Exception as exc:
            result.update(seconds=round(time.monotonic() - t0, 3), status="error",
                          error=str(exc)[:150])

    thread = threading.Thread(target=work, daemon=True)
    thread.start()
    if not started.wait(3):
        raise RuntimeError("B did not start")
    return thread, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="confirm disposable TP lab")
    args = parser.parse_args()
    if not args.run:
        parser.error("No connections opened: pass --run after confirming lab scope")
    a = b = None
    table_locked = False
    try:
        a, b = connect(), connect()
        ca, cb = a.cursor(), b.cursor()
        ca.execute("SELECT @@version, CONNECTION_ID()")
        version, aid = ca.fetchone()
        cb.execute("SELECT CONNECTION_ID(), @@autocommit")
        bid, bauto = cb.fetchone()
        ca.execute("SHOW TABLE STATUS LIKE 'reserva'")
        metadata = ca.fetchone()
        if a.database != "hotel_db" or b.database != "hotel_db" or metadata[1] != "InnoDB" or bauto != 1:
            raise RuntimeError("Unexpected database, engine or B autocommit")
        ca.execute("SELECT id_reserva, estado_reserva FROM reserva ORDER BY id_reserva LIMIT 1")
        id_value, original = ca.fetchone()
        cb.execute("SET SESSION lock_wait_timeout = 6")
        cb.execute("SET SESSION innodb_lock_wait_timeout = 6")
        report = {"version": version, "connections": [aid, bid], "id_reserva": id_value}

        ca.execute("LOCK TABLES reserva READ")
        table_locked = True
        cb.execute("SELECT id_reserva FROM reserva WHERE id_reserva = %s", (id_value,))
        report["table_plain_select"] = cb.fetchone()[0] == id_value
        thread, outcome = one_wait(b, "UPDATE reserva SET estado_reserva = estado_reserva WHERE id_reserva = %s", id_value)
        time.sleep(1.5)
        report["table_wait_observed"] = thread.is_alive()
        ca.execute("UNLOCK TABLES")
        table_locked = False
        thread.join(8)
        report["table_write"] = outcome
        if thread.is_alive():
            raise RuntimeError("B table-lock UPDATE did not finish after unlock")

        ca.execute("START TRANSACTION")
        ca.execute("SELECT id_reserva FROM reserva WHERE id_reserva = %s FOR UPDATE", (id_value,))
        if ca.fetchone() is None:
            raise RuntimeError("Reservation disappeared")
        t0 = time.monotonic()
        cb.execute("SELECT estado_reserva FROM reserva WHERE id_reserva = %s", (id_value,))
        report["row_plain_select_seconds"] = round(time.monotonic() - t0, 3)
        cb.fetchone()
        thread, outcome = one_wait(b, "UPDATE reserva SET estado_reserva = estado_reserva WHERE id_reserva = %s", id_value)
        time.sleep(1.5)
        report["row_wait_observed"] = thread.is_alive()
        a.rollback()
        thread.join(8)
        report["row_write"] = outcome
        if thread.is_alive():
            raise RuntimeError("B row-lock UPDATE did not finish after rollback")
        ca.execute("SELECT estado_reserva FROM reserva WHERE id_reserva = %s", (id_value,))
        report["value_unchanged"] = ca.fetchone()[0] == original
        print(json.dumps(report, ensure_ascii=False, indent=2))
        ca.close()
        cb.close()
    finally:
        if a is not None:
            try:
                if table_locked:
                    a.cursor().execute("UNLOCK TABLES")
                a.rollback()
            finally:
                a.close()
        if b is not None:
            b.close()


if __name__ == "__main__":
    main()
