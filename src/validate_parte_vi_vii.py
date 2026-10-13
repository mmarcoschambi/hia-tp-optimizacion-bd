"""Offline contract checks for the PDF points 31–37 experiment script.

This does not claim SQL parse success or execution against hotel_db.
"""
from pathlib import Path
import re

sql = (Path(__file__).with_name("parte_vi_vii_experimentos.sql")).read_text(encoding="utf-8")
for tag in ("P31", "P32", "P33"):
    assert re.search(rf"^-- {tag}\b", sql, re.M), f"missing {tag}"
for n in range(1, 9):
    for stage in ("original", "optimized"):
        assert re.search(rf"^-- Q{n} {stage}(?:\s|:|$)", sql, re.M), f"missing Q{n} {stage}"
assert len(re.findall(r"\bEXPLAIN FORMAT=JSON\b", sql, re.I)) >= 18
assert "ANALYZE TABLE reserva" in sql
assert "information_schema.STATISTICS" in sql
assert "JOIN habitacion" in sql
assert "idx_pvii_guest_date" in sql
assert "idx_pvii_date_guest" in sql
runner = (Path(__file__).with_name("run_parte_vi_vii_lab.py")).read_text(encoding="utf-8")
for guard in ("max_statement_time", "DB_PASSWORD", "--run", "EXPLAIN FORMAT=JSON", "idx_pvii_guest_date", "idx_pvii_keyset"):
    assert guard in runner, f"missing runner guard: {guard}"
payload = (Path(__file__).with_name("run_parte_vi_vii_payload.py")).read_text(encoding="utf-8")
for guard in ("--run", "max_statement_time", "query_cache_type", "fetchmany", "rollback", "sha256", "multiset_sha256", "Q8"):
    assert guard in payload, f"missing payload benchmark guard: {guard}"
print("OK: offline structural contract for PDF 31-37; use lab runners for measurements")
