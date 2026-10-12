"""Deterministic structural validation for Parte V SQL queries.

This validator intentionally avoids connecting to hotel_db: it checks that the
assignment script contains the required business-query sections and SQL constructs.
It is meant to be reproducible in any local checkout, including environments
without MySQL/MariaDB running.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "src" / "parte_v_consultas_negocio.sql"

REQUIRED_PATTERNS: dict[str, list[tuple[str, str]]] = {
    "P24": [
        ("COUNT", r"\bCOUNT\s*\("),
        ("SUM", r"\bSUM\s*\("),
        ("date range filter", r"fecha_inicio\s*>=.*fecha_inicio\s*<"),
        ("status filter", r"estado_reserva\s*="),
    ],
    "P25": [
        ("INNER JOIN huesped", r"INNER\s+JOIN\s+huesped"),
        ("LEFT JOIN history", r"LEFT\s+JOIN\s+historial_huesped"),
    ],
    "P26": [
        ("occupancy CTE", r"noches_ocupadas"),
        ("hotel join", r"JOIN\s+hotel"),
        ("room type join", r"JOIN\s+tipo_habitacion"),
        ("occupancy percentage", r"porcentaje_ocupacion"),
    ],
    "P27": [
        ("EXISTS", r"\bEXISTS\s*\("),
        ("HAVING", r"\bHAVING\b"),
        ("cancelled status", r"estado_reserva\s*=\s*'Cancelada'"),
    ],
    "P28": [
        ("CASE WHEN", r"\bCASE\b[\s\S]*\bWHEN\b"),
        ("segment alias", r"segmento_cliente"),
    ],
    "P29": [
        ("GROUP BY", r"\bGROUP\s+BY\b"),
        ("HAVING", r"\bHAVING\b"),
        ("performance ORDER BY", r"ORDER\s+BY\s+ingreso_estimado\s+DESC"),
    ],
    "P30": [
        ("keyset tuple comparison", r"\(r\.fecha_inicio,\s*r\.id_reserva\)\s*>"),
        ("LIMIT page size", r"LIMIT\s+@p30_page_size"),
    ],
}


def extract_section(sql: str, point: str) -> str:
    pattern = re.compile(
        rf"-- {point}:.*?(?=\n-- ={{20,}}\n-- P\d{{2}}:|\Z)",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(sql)
    if not match:
        raise AssertionError(f"Missing section {point}")
    return match.group(0)


def assert_balanced_parentheses(sql: str) -> None:
    balance = 0
    for index, char in enumerate(sql):
        if char == "(":
            balance += 1
        elif char == ")":
            balance -= 1
        if balance < 0:
            raise AssertionError(f"Unbalanced parentheses near character {index}")
    if balance != 0:
        raise AssertionError("Unbalanced parentheses at end of SQL file")


def strip_sql_comments(sql: str) -> str:
    without_block_comments = re.sub(r"/\*[\s\S]*?\*/", "", sql)
    return re.sub(r"--.*", "", without_block_comments)


def main() -> None:
    sql = SQL_PATH.read_text(encoding="utf-8")
    executable_sql = strip_sql_comments(sql)
    assert_balanced_parentheses(sql)

    for point, checks in REQUIRED_PATTERNS.items():
        section = extract_section(sql, point)
        for description, pattern in checks:
            if not re.search(pattern, section, re.IGNORECASE | re.DOTALL):
                raise AssertionError(f"{point}: missing {description}")

    p30_executable = strip_sql_comments(extract_section(sql, "P30"))
    if re.search(r"\bOFFSET\b", p30_executable, re.IGNORECASE):
        raise AssertionError("P30 must avoid executable OFFSET; use keyset pagination")

    statement_count = len([chunk for chunk in executable_sql.split(";") if chunk.strip()])
    if statement_count < 14:
        raise AssertionError(f"Expected at least 14 SQL statements, found {statement_count}")

    print("OK: Parte V SQL structure validated for P24-P30")
    print(f"OK: {statement_count} SQL statements/comments blocks found")
    print(f"OK: validated file {SQL_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
