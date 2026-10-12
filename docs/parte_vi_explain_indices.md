# PDF 31–37: optimizer and eight optimization experiments

Scope follows the **course PDF, page 5**, not issue #3's provisional numbering: 31–33 are Parte VI and 34–37 are Parte VII. The original issue's leftmost-prefix demonstration is retained as an additional index experiment below; PDF 38–39 belong to concurrency. The local MariaDB 10.6.23 `hotel_db` was explicitly authorized by the user as a disposable TP lab. Bounded plans, index builds, SELECT/count variants and rollback-only UPDATE probes were executed through Python connector. All four experimental indexes were dropped after the measurements; see below for single-run evidence and limitations.

## Reproduce without changing production

Use MySQL 8.0+ (or check your MariaDB JSON layout) on an authorized disposable `hotel_db` copy. Verify schema, indexes, engine, version and cache state. The loader's `AUTO_INCREMENT=6000001` is not proof of the current row count: even with a 60-second statement limit, exact `COUNT(*)` timed out (MariaDB error 1969). InnoDB estimated rows moved from 5,740,499 to roughly 5,980,000 after `ANALYZE TABLE`. Existing Parte V index recommendations in `src/parte_v_consultas_negocio.sql` are commented, not guaranteed installed. Run `src/parte_vi_vii_experimentos.sql` in a CLI with captured output; manually run the SELECT after each EXPLAIN by removing only `EXPLAIN FORMAT=JSON`, capture duration and row count, repeat at least five times on an unchanged snapshot and report median and spread. For comparisons requiring new indexes, run the marked DDL on the copy, `ANALYZE TABLE reserva`, rerun **both** plans and timings (not just one). Do not force an index to claim an optimizer win. `ANALYZE TABLE` and index builds can change plans, use IO and take locks; schedule off production. For Q8 find the actual row 1000 using `ORDER BY fecha_inicio,id_reserva LIMIT 999,1` in the same consistent snapshot and substitute its tuple for the example cursor; otherwise pages are not equivalent. Locking tests are separate.

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

P35 requires executing **both** query versions and measuring, not just EXPLAIN; P36's alternatives cover SARGability, covering/projection, composite indexes, JOIN and pagination. P37: measure secondary-index bytes (`information_schema.TABLES.INDEX_LENGTH` as rough table-level estimate) and representative write throughput/latency before/after on the copy; report any other query regressions. Observed timings below are one bounded run per variant (not the five repeats recommended above). For Q1–Q6 the runner times a derived `COUNT(*)` variant to avoid transporting millions of rows; this is **not** the payload SELECT's runtime or necessarily its plan. Q7 fetches payload, Q8 fetches actual pages.

## Leftmost-prefix supplemental experiment (issue request, not PDF P38–39)

For `idx_pvii_guest_date (id_huesped,fecha_inicio)`, compare `WHERE id_huesped=42`, `WHERE id_huesped=42 AND fecha_inicio >= '2024-01-01'`, and `WHERE fecha_inicio >= '2024-01-01'`. The last query cannot ordinarily seek by the second key part alone; some versions can choose a skip scan or full index scan, so check `access_type` and `used_key_parts`, not only `key`. An equality on first part plus range on second is generally useful; a range on first limits subsequent parts for seeking. `YEAR(fecha_inicio)`, implicit incompatible conversions (dependent on actual column type), and leading-wildcard `LIKE '%foo'` may prevent a normal B-tree seek, but the optimizer can still scan an index or use another one. Compare genuinely equivalent predicates and record measured plans; do not infer index usage solely from SQL text.

## Observed read-only plan sample (local MariaDB 10.6.23)

Connected to local `hotel_db` with Python connector; `information_schema.TABLES.TABLE_ROWS` reported **5,740,499 estimated rows** (not an exact `COUNT(*)` or confirmation of 6M). `SHOW INDEX FROM reserva` returned `PRIMARY(id_reserva)`, `id_habitacion(id_habitacion)`, `id_huesped(id_huesped)`; no date or status index. These are **EXPLAIN estimates**, not runtime measurements. The initial attempt at exact `COUNT(*)` exceeded 45 seconds and was interrupted; no result was recorded.

| Plan | MariaDB JSON `access_type`, `key`, `rows`, `filtered` | Interpretation |
| --- | --- | --- |
| Q1 original `YEAR(fecha_inicio)=2024` | `ALL`, none, 5,740,499, 100 | Function inhibits a date seek |
| Q1 range rewrite | `ALL`, none, 5,740,499, 100 | No date index exists; SARGability alone cannot improve this observed plan |
| Q3 `id_huesped + 0 = 42` | `index`, `id_huesped`, 5,740,499, 100 | Full covering-index scan; a non-null `key` does not prove selective seeking |
| Q3 `id_huesped = 42` | `ref`, `id_huesped`, 18, 100 | Estimated 18 matching index entries |
| P32 `estado_reserva='Finalizada'` | `ALL`, none, 5,740,499, 100 | No status index; not evidence of a cost-based rejection of an existing one |

Actual observed MariaDB JSON subtrees (trimmed to relevant fields; **not MySQL `cost_info`**):

```json
{"query_block":{"table":{"table_name":"reserva","access_type":"index","key":"id_huesped","used_key_parts":["id_huesped"],"rows":5740499,"filtered":100,"attached_condition":"reserva.id_huesped + 0 = 42","using_index":true}}}
{"query_block":{"table":{"table_name":"reserva","access_type":"ref","possible_keys":["id_huesped"],"key":"id_huesped","used_key_parts":["id_huesped"],"ref":["const"],"rows":18,"filtered":100,"using_index":true}}}
```

MariaDB 10.6 emitted `rows` rather than MySQL's `rows_examined_per_scan`, and these plans have **no `cost_info.query_cost` field**. Do not invent costs or treat `filtered=100` as measured selectivity. Offline structural validation: `python src/validate_parte_vi_vii.py`. Separately, all **22 read-only `EXPLAIN FORMAT=JSON` statements** in `src/parte_vi_vii_experimentos.sql` executed successfully via Python connector on the local MariaDB 10.6 server (comments removed; no DDL, ANALYZE or SELECT payload executed in that pass). The original 22 read-only plans preceded user authorization; later indexed experiments, statistics refresh and measured results follow. Exact row count and repeated latency distributions remain unavailable.

## Observed P31–33: statistics, cost choice, JOIN

Baseline index cardinality estimate for `id_huesped` was 1,148,099; after building experimental indexes and running `ANALYZE TABLE reserva`, it was 1,195,863. `TABLE_ROWS` moved from 5,740,499 to 5,979,316 (samples, **not actual counts**). Four owned indexes were built: guest/date (58.641 s), date/guest (47.745 s), status/date (76.509 s), and date/reservation ID (38.102 s). `ANALYZE TABLE` returned OK each time. Date-leading versus guest-leading indexes are not interchangeable.

For P32, after adding `idx_pvii_state_date`, `SELECT * WHERE estado_reserva='Finalizada'` chose `ALL` (estimated 5,984,088 rows; `filtered=50`) despite this possible index; `SELECT id_reserva` with the same filter chose `ref` on the covering index (estimated 2,992,044 rows). A large fraction of rows and non-covering row lookups can make a full table scan preferable. MariaDB 10.6's `EXPLAIN FORMAT=JSON` did **not** emit `cost_info.query_cost`; the cost explanation is qualitative, not a claimed numeric cost comparison.

The real `habitacion` table has **zero rows**. Thus the original P33/Q6 JOIN returns zero in both forms and cannot demonstrate a business-query speedup: the bulk loader disabled FK checks while inserting reservations. To test the access rule without fabricating populated master data, `--stage join-fixture` creates and drops a connection-local InnoDB `tp_habitacion` containing 18 room IDs from guest 42. Both JOIN variants returned 18 rows (one run: expression 0.0024 s, direct 0.0019 s). The expression used a block nested loop over the 18-row fixture; direct equality yielded `eq_ref` on its primary key, one row per lookup. This tiny fixture establishes the access difference, **not** scalable production JOIN performance. Key JSON tree excerpts:

```json
{"query_block":{"table":{"table_name":"r","access_type":"ref","key":"id_huesped","rows":18},"block-nl-join":{"table":{"table_name":"ha","access_type":"index","key":"PRIMARY","rows":18},"join_type":"BNL","attached_condition":"ha.id_habitacion + 0 = r.id_habitacion"}}}
{"query_block":{"table":{"table_name":"ha","access_type":"eq_ref","key":"PRIMARY","ref":["hotel_db.r.id_habitacion"],"rows":1}}}
```

## Observed P34–37: one bounded run per pair

Run `python src/run_parte_vi_vii_lab.py --run --stage baseline`, add each index via `--stage add-index --index <owned-name>`, then `--stage indexed`. The script has a 12-second per-statement ceiling for SELECTs; a timeout is **not** a latency measurement. For Q8, use `(fecha_inicio,id_reserva)`, not `(fecha_inicio,id_huesped)`, to avoid a multi-million-row filesort. These are plan estimates and observed wall-clock times from separate runs, not medians or controlled cold-cache comparisons.

| Pair | Baseline → indexed JSON plan | One-run measurement, original → alternative | Result / limitation |
| --- | --- | --- | --- |
| Q1 | `ALL` 5.74M → `index` ~5.98M vs `range` ~2.99M | original timeout >12 s → 2.701 s; alternative 10.540 s → 1.971 s | Same 2,192,393 qualifying rows in indexed count variants; original baseline timed out. Wide year range reduces gain. |
| Q2 | `ALL` both → `index` ~5.98M vs `range` 6,003 | 9.521 s → 9.152 s baseline; 3.566 s → 0.002 s indexed | Same 6,003 qualifying rows; strong benefit for selective date. |
| Q3 | `index` ~5.74M vs `ref` 18; same access types indexed | original >12 s both runs; equality 0.001 s | Expression still scans covering index; baseline original also timed out. |
| Q4 | `ref` 18 → `range` 9 (`id_huesped,fecha_inicio`) | baseline 0.240 s / 0.002 s (identical SQL, cache); indexed 0.001 s / 0.001 s | Nine matching rows. Do **not** interpret within-stage duplicate timing as before/after improvement. |
| Q5 | `ALL` ~5.74M → `range` ~59,576 (`estado_reserva,fecha_inicio`) | baseline 9.029 / 8.675 s; indexed 0.044 / 0.010 s | 27,627 matching rows; both duplicate copies are the same SQL within each stage. |
| Q6 | Real JOIN: empty `habitacion`; fixture expression `BNL` → direct `eq_ref` | fixture 0.0024 → 0.0019 s, 18 rows each | Only fixture supports an access comparison; real table gives zero rows. |
| Q7 | `ref` 18 both; narrow result may be covered | 1,083 → 412 bytes, 18 rows (Python JSON approximation); sample timings 0.337 → 0.001 s indexed | Different projections; not equal payload semantics or a reliable speedup estimate. |
| Q8 | `index` ~1,020 → `range` ~2.99M estimate using explicit OR | 0.002 → 0.272 s, 20 rows each; pages identical | At OFFSET 1000, keyset was **slower** in this run; cursor acquisition extra. Tuple comparison selected an index scan, not range. |

Q8's `range` estimated rows counts a broad date range, not actual 20 visited rows; neither this estimate nor `filtered=100` proves runtime selectivity. Q1–Q6 times are for count variants; Q7/Q8 fetch actual rows. The lab had no representative data for P33's real JOIN. Repeat with warm/cold controls and actual payload SELECTs before asserting a general latency improvement.

### P37 side effects and restoration

InnoDB `Index_length` was ~268,992,512 bytes before builds and ~740,474,880 bytes with all four indexes (rough approximate metadata; after dropping and `ANALYZE TABLE`, ~298,352,640 bytes, so it is not an exact byte delta). Seven single-row `UPDATE estado_reserva,fecha_inicio` probes were rolled back individually; first indexed probe took 2724 ms (cold/outlier), subsequent six **1.968–2.847 ms**; after removing indexes, seven probes were **0.745–1.361 ms**. The original row was verified unchanged in both stages. These order-dependent, single-row, rollback-only samples suggest index-maintenance overhead, **not** representative INSERT/UPDATE/DELETE throughput. INSERT/DELETE were not measured; master tables are empty and the loader previously disabled FK checks. All four owned indexes were dropped and `ANALYZE TABLE reserva` returned OK; `SHOW INDEX` again listed only `PRIMARY`, `id_habitacion`, `id_huesped`. Do not infer a stable write regression from these unpaired samples.

### Observed leftmost prefix and SARGability

With `FORCE INDEX(idx_pvii_guest_date)` solely to isolate the rule, `id_huesped=42` used `ref` (18 estimated); guest equality plus date range used `range` on both key parts (13 estimated); **date alone** used an `index` scan of ~5,979,316 entries instead of a seek. Without the force, the optimizer chose date-leading `idx_pvii_date_guest` for a one-day `range` (~6,003 estimated). The forced comparison demonstrates index structure, **not** a tuning recommendation.

With `idx_pvii_state_date` temporarily present, `LIKE '%ncelada'` on status scanned the whole covering index (~5,984,088 estimated), while `LIKE 'Cancela%'` used `range` (~1,998,758 estimated). The `YEAR()` and `DATE()` cases above similarly prevent a normal date range seek. A string literal `'42x'` compared to integer `id_huesped` still produced `ref` (18 estimated) through coercion on MariaDB 10.6: incompatible types do **not** universally turn indexes off, but may silently change predicate meaning. No rows were fetched for that coercion probe. All such plans are version/data dependent and none imply an automatic speedup.
