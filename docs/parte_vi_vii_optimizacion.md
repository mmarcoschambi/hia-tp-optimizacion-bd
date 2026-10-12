# PDF 31–37: optimizer and eight optimization experiments

Scope follows the **course PDF, page 5**, not issue #3's provisional numbering: 31–33 are Parte VI and 34–37 are Parte VII. The original issue's leftmost-prefix demonstration is retained as an additional index experiment below; PDF 38–39 belong to concurrency. This document is an **experiment protocol, not observed benchmark results**: no MySQL/MariaDB server/client was available in this checkout.

## Reproduce without changing production

Use MySQL 8.0+ (or check your MariaDB JSON layout) on a disposable `hotel_db` copy with the same schema, 6M `reserva` rows and distribution. Confirm actual `COUNT(*)`, `SHOW CREATE TABLE reserva`, `SHOW INDEX FROM reserva`, version, engine, buffer/cache state and SQL mode. Existing Parte V index recommendations in `src/parte_v_consultas_negocio.sql` are commented, not guaranteed installed. Run `src/parte_vi_vii_experimentos.sql` in a CLI with captured output; manually run the SELECT after each EXPLAIN by removing only `EXPLAIN FORMAT=JSON`, capture duration and row count, repeat at least five times on an unchanged snapshot and report median and spread. For comparisons requiring new indexes, run the marked DDL on the copy, `ANALYZE TABLE reserva`, rerun **both** plans and timings (not just one). Do not force an index to claim an optimizer win. `ANALYZE TABLE` and index builds can change plans, use IO and take locks; schedule off production. For Q8 find the actual row 1000 using `ORDER BY fecha_inicio,id_reserva LIMIT 999,1` in the same consistent snapshot and substitute its tuple for the example cursor; otherwise pages are not equivalent. Locking tests are separate.

Record one row per variant: engine/version, schema/indexes, distribution, estimated `access_type`, `possible_keys`, `key`, `used_key_parts`, `rows_examined_per_scan`, `rows_produced_per_join`, `filtered`, `cost_info.query_cost` (if emitted), `using_temporary_table`, `using_filesort`, actual result rows/bytes, elapsed median/range, and whether warmed or cold. `EXPLAIN` estimates do not measure elapsed runtime; use `EXPLAIN ANALYZE` only if the engine supports it, separately recording actual rows/time. Costs are optimizer units, not milliseconds and not directly comparable across engine versions.

### Reading the JSON cost tree

Typical MySQL shape (field names/availability vary by version, **schema sketch, not a captured plan**):

```json
{"query_block":{"cost_info":{"query_cost":"<estimated units>"},"nested_loop":[{"table":{"table_name":"r","access_type":"<ALL|range|ref|eq_ref>","possible_keys":["<candidate>"],"key":"<chosen or null>","used_key_parts":["<prefix>"],"rows_examined_per_scan":"<estimate>","rows_produced_per_join":"<estimate>","filtered":"<percent>","cost_info":{"read_cost":"<estimate>","eval_cost":"<estimate>"}}}]}}
```

In a JOIN, read `nested_loop` order: outer estimated rows multiplied by inner lookups. A high `filtered` means a larger share survives the condition; it is not the number of rows visited. An `ALL` plan can be rational when most rows qualify (e.g. `Finalizada`, around 65% in the generator), while a selective guest ID may favor `ref`. Cardinality derives from sampled index statistics and distribution; compare estimates to `COUNT(*)` by status and after `ANALYZE TABLE reserva` (P31). Sampling, stale statistics, skew and buffer state explain surprises, not proof of an optimizer bug. P33's direct FK equality may permit `eq_ref` on `habitacion`'s PK; an expression on that column may suppress that access, though join reordering and actual keys can change the result.

## P34–37: hypotheses for eight query pairs

| Pair | Original → alternative | Hypothesis / comparable outcome | Additional costs / caveats |
| --- | --- | --- | --- |
| Q1 | `YEAR(fecha_inicio)` → half-open date range | Same rows; range on first date key part can reduce reads | Depends on date distribution and existing index |
| Q2 | `DATE(fecha_inicio)` → one-day half-open range | Same rows for DATE/DATETIME; seek possible | Verify timezone semantics if using TIMESTAMP |
| Q3 | `id_huesped + 0` → direct equality | Same numeric IDs; direct predicate can use leading guest key | Confirm integer schema before claiming equivalence |
| Q4 | guest+date before/after `(id_huesped,fecha_inicio)` | Identical SQL; range after equality prefix may help | Index storage and INSERT/UPDATE/DELETE overhead |
| Q5 | status+date before/after `(estado_reserva,fecha_inicio)` | Identical SQL; range after status equality | Low-selectivity status alone may still scan |
| Q6 | computed JOIN equality → direct equality | Same rows for integer keys; index lookup may improve | Join order and FK/PK availability matter |
| Q7 | `SELECT *` → two columns | Same filtering, smaller payload (not identical projection) | Only valid if caller needs the two columns |
| Q8 | OFFSET 1000 → keyset after actual row 1000 | Same page under stable snapshot and unique order | Cursor acquisition is extra cost; updates between pages change results |

P35 requires executing **both** query versions and measuring, not just EXPLAIN; P36's alternatives cover SARGability, covering/projection, composite indexes, JOIN and pagination. P37: measure secondary-index bytes (`information_schema.TABLES.INDEX_LENGTH` as rough table-level estimate) and representative write throughput/latency before/after on the copy; report any other query regressions. None of these runtime validations has been performed here.

## Leftmost-prefix supplemental experiment (issue request, not PDF P38–39)

For `idx_pvii_guest_date (id_huesped,fecha_inicio)`, compare `WHERE id_huesped=42`, `WHERE id_huesped=42 AND fecha_inicio >= '2024-01-01'`, and `WHERE fecha_inicio >= '2024-01-01'`. The last query cannot ordinarily seek by the second key part alone; some versions can choose a skip scan or full index scan, so check `access_type` and `used_key_parts`, not only `key`. An equality on first part plus range on second is generally useful; a range on first limits subsequent parts for seeking. `YEAR(fecha_inicio)`, implicit incompatible conversions (dependent on actual column type), and leading-wildcard `LIKE '%foo'` may prevent a normal B-tree seek, but the optimizer can still scan an index or use another one. Compare genuinely equivalent predicates and record measured plans; do not infer index usage solely from SQL text.

## Status

Offline structural validation is available via `python src/validate_parte_vi_vii.py`. Live plans, eight paired timings, real JSON cost trees and write-side-effect measurements are **pending** a provisioned disposable database. No cost or timing in this document is an observation.
