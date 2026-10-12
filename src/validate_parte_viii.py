"""Offline guardrails for the manually coordinated two-connection experiment."""
from pathlib import Path

root = Path(__file__).parent
for name, markers in {
    "parte_viii_session_a.sql": ("P38 TABLE", "P38 ROW", "P39 ROW", "UNLOCK TABLES", "ROLLBACK"),
    "parte_viii_session_b.sql": ("P38 TABLE", "P38 ROW", "P39 ROW", "innodb_lock_wait_timeout", "lock_wait_timeout"),
}.items():
    text = (root / name).read_text(encoding="utf-8")
    for marker in markers:
        assert marker in text, f"{name}: missing {marker}"
    assert "DELETE FROM" not in text.upper(), f"{name}: destructive delete"
print("OK: offline structure for PDF 38-39; actual blocking not observed")
