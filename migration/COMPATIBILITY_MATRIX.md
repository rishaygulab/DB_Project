# Compatibility matrix: Oracle PL/SQL → MariaDB `sql_mode=ORACLE`

**Question answered, per object:** what happened when the Oracle source ran under `SET sql_mode=ORACLE`?

| | |
|---|---|
| Source | `corpus/oracle/lms/` (Library Management System, Oracle 12c+), untouched |
| Target | `corpus/mariadb/lms/`, **MariaDB 11.8.9 LTS** (pinned), cross-checked on **MariaDB 13.0.2** |
| Session settings | `sql_mode=ORACLE,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,EMPTY_STRING_IS_NULL`, `autocommit=0`, database collation `utf8mb4_nopad_bin` ([why](SILENT_DIFFERENCES.md)) |
| Migration diff | [`corpus.diff`](corpus.diff): every changed line carries a `-- MIGRATION:` comment |
| Evidence | [`probes/`](probes/) (one probe per Oracle feature), [`verify/`](verify/) (62 object-level cases) |

## Headline

Of the **39 schema objects** (sequences, tables, indexes, functions, procedures, triggers, views):

| Bucket | Count | Objects |
|---|---|---|
| **1. Runs unchanged** | **29** (74%) | 27 have byte-identical source and need nothing else. 2 (`return_book`, `pay_fine`) have identical source but call the shared shim in `00_compat.sql`. |
| **2. Runs after a change** | **10** (26%) | `loans`, `book_audit`, `ix_books_title`, `fn_calc_fine`, `issue_book`, 3 triggers, `v_book_catalog`, `v_overdue_loans` |
| **3. No equivalent** | **0 objects** | 2 *scripts* were redesigned: `01_drop.sql` (data dictionary loop) and `run_all.sql` (SQL*Plus) |

- **Size of the change:** in `02`–`06`, 82 added or removed code lines against 609 lines of Oracle code (comments and blank lines excluded). The 1-to-3 trigger split and the re-indentation inside the new `IF` blocks account for most of the 64 in `03_plsql.sql`. All 60 data-load statements (`04_data.sql`) are unchanged.
- **Starting point:** loading the unchanged Oracle files under plain `sql_mode=ORACLE` runs 75 of 123 statements. Most of the 48 failures cascade from one table (`LOANS`) whose DEFAULT is rejected. The isolated probes separate the real causes from the cascade ([`probes/baseline_unchanged.json`](probes/baseline_unchanged.json)).
- **Verification:** **62/62** cases pass on 11.8 and on 13.0. With only `SET sql_mode=ORACLE` (default collation, autocommit on), **7 cases return wrong results with no error** ([details](SILENT_DIFFERENCES.md)).
- **On MariaDB 13.0** the original multi-event `trg_books_audit` runs unchanged, and so do `TRUNC(date)` and `DEFAULT TRUNC(SYSDATE)`. That moves 1 object from bucket 2 to bucket 1 and makes the `TRUNC` shim unnecessary.

> **What "Verified" means here.** *Yes* = the MariaDB result matches the result Oracle's semantics require: the business rules in `corpus/oracle/lms/03_plsql.sql`, the expected values in `04_data.sql`'s comments, and Oracle's documented behaviour. The cases are in [`verify/cases.json`](verify/cases.json). A side-by-side run against the Oracle reference container is the harness's job (Person 3), and the case file is written so it can be reused there.

## Object matrix

Status values: **unchanged** · **unchanged + shim** (source identical, calls a `00_compat.sql` shim) · **rewritten** · **no equivalent**.

### Sequences, tables, indexes (`02_schema.sql`)

| Object | Type | Status | Change | Why | Verified |
|---|---|---|---|---|---|
| SEQ_MEMBER … SEQ_AUDIT (9) | sequence | unchanged | none | `CREATE SEQUENCE … NOCACHE` and `DEFAULT seq.NEXTVAL` are supported (probe T2) | yes: ids 1..n in every query, `issue_book` returns 9 |
| MEMBERS | table | unchanged | none | VARCHAR2, NUMBER, DATE, CHECK with LIKE, `DEFAULT SYSDATE` all supported (T1, T3, T9) | yes: 4 cases (NULL/collation constraints) |
| AUTHORS, PUBLISHERS, CATEGORIES, STAFF | table | unchanged | none | same | yes: indirectly (load + Q1–Q10) |
| BOOKS | table | unchanged | none | multi-column CHECK and FKs supported | yes: trigger and view cases |
| BOOK_AUTHORS | table | unchanged | none | composite PK, `ON DELETE CASCADE` | yes: `trg_books_audit` delete case |
| FINES | table | unchanged | none | failed in the unchanged run only because `LOANS` did not exist yet | yes: `return_book`, `pay_fine`, divide-by-zero case |
| LOANS | table | rewritten | `DEFAULT TRUNC(SYSDATE)` → `DEFAULT CURRENT_DATE` | 11.8 has no `TRUNC(date)`, and stored functions are not allowed in DEFAULT (T4). Runs unchanged on 13.0. | yes: `loan_date default is today` |
| BOOK_AUDIT | table | rewritten | `DEFAULT USER` → `DEFAULT (SUBSTRING_INDEX(USER(),'@',1))`; `TIMESTAMP DEFAULT SYSTIMESTAMP` → `TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6)` | `USER` and `SYSTIMESTAMP` are not keywords here (T5, T6). `USER()` returns `user@host`, so the host is stripped to store what Oracle stores. `(6)` keeps Oracle's microsecond precision. | yes: `changed_by is the bare user name` |
| IX_BOOKS_CATEGORY, IX_BOOKS_PUBLISHER, IX_BA_AUTHOR, IX_LOANS_MEMBER, IX_LOANS_BOOK, IX_LOANS_OPEN | index | unchanged | none | plain B-tree indexes | yes: created on load |
| IX_BOOKS_TITLE | index | rewritten | `ON books(UPPER(title))` → invisible virtual column `title_upper AS (UPPER(title))` + index on it | no function-based indexes (T8). The column is `INVISIBLE`, so `SELECT *` output is unchanged. | yes: `EXPLAIN` of `WHERE UPPER(title)=…` uses the index on 11.8 |

### Functions, triggers, procedures (`03_plsql.sql`)

| Object | Type | Status | Change | Why | Verified |
|---|---|---|---|---|---|
| FN_LOAN_DAYS | function | unchanged | none | `RETURN CASE …`, VARCHAR2 parameter (F7) | yes: 7 cases, incl. `''`, NULL, `'student'`, `'STUDENT '` |
| FN_MEMBER_DUES | function | unchanged | none | `SELECT NVL(SUM(..),0) INTO`, JOIN (F4) | yes: 4 cases |
| FN_CALC_FINE | function | rewritten | `CONSTANT` removed; `(TRUNC(a) - TRUNC(b))` → `DATEDIFF(a, b)` | `CONSTANT` is not accepted (T10). **`DATE - DATE` is not a day count** (F2b): it returned `5000000` for 5 days and `76000000` for 6 days across a month, with no error. `TRUNC` comes from the shim on 11.8. | yes: 8 cases, incl. across month/year, time of day, NULLs |
| TRG_LOANS_AI | trigger | rewritten | `WHEN (NEW.return_date IS NULL)` → `IF :NEW.return_date IS NULL THEN … END IF` in the body | trigger `WHEN` clause not supported on 11.8 or 13.0 (R2) | yes: 3 cases |
| TRG_LOANS_AU_RETURN | trigger | rewritten | `WHEN (…)` → `IF` in body | same (R2). `AFTER UPDATE OF return_date` works and honours the column list (follow-up probe). | yes: 3 cases |
| TRG_BOOKS_AUDIT | trigger | rewritten (11.8) / **unchanged (13.0)** | split into `trg_books_audit_ai/_au/_ad`, one per branch | 11.8 has no `INSERT OR DELETE OR UPDATE` (R4) and no `INSERTING/UPDATING` (R5). 13.0 runs the original. | yes: 4 cases on 11.8; original text verified on 13.0 |
| ISSUE_BOOK | procedure | rewritten | `… RETURNING loan_id INTO p_loan_id` → `p_loan_id := seq_loan.CURRVAL`; `TRUNC(SYSDATE) + n` → `ADDDATE(TRUNC(SYSDATE), n)` | no `RETURNING … INTO` (P6). **`DATE + n` adds n *seconds* to a DATE value** (F3b), so the due date came out as today 00:00:14, with no error. `CURRVAL` is per session, as in Oracle. `RAISE_APPLICATION_ERROR` comes from the shim. | yes: 12 cases: every error path −20001…−20005, message text, OUT param, no partial writes |
| RETURN_BOOK | procedure | unchanged + shim | none | `SQL%ROWCOUNT`, `DEFAULT TRUNC(SYSDATE)` parameter, `COMMIT` all supported. It **compiled without the shim but failed at runtime** (`RAISE_APPLICATION_ERROR`/`TRUNC` do not exist), so a successful CREATE proves nothing. | yes: 5 cases |
| PAY_FINE | procedure | unchanged + shim | none | as above | yes: 3 cases |

### Views (`05_views.sql`)

| Object | Type | Status | Change | Why | Verified |
|---|---|---|---|---|---|
| V_BOOK_CATALOG | view | rewritten | `LISTAGG(a.name, ', ') WITHIN GROUP (ORDER BY a.name)` → `GROUP_CONCAT(a.name ORDER BY a.name SEPARATOR ', ')` | no `LISTAGG` on 11.8 or 13.0 (F9). Same NULL result for a book with no authors. | yes: 2 cases |
| V_ACTIVE_LOANS | view | unchanged | none | `||` concatenation is NULL-safe in Oracle mode (F6, N6) | yes |
| V_OVERDUE_LOANS | view | rewritten | `TRUNC(SYSDATE) - l.due_date` → `DATEDIFF(SYSDATE, l.due_date)` | same `DATE - DATE` trap as `fn_calc_fine` | yes: days overdue and fine |
| V_MEMBER_SUMMARY | view | unchanged | none | `COUNT(CASE …)`, calls a stored function | yes: 2 cases (see the note on an inherited bug below) |

### Scripts, data, queries (`01_drop.sql`, `04_data.sql`, `06_queries.sql`, `run_all.sql`)

| Object | Type | Status | Change | Why | Verified |
|---|---|---|---|---|---|
| 01_drop.sql | script | **no equivalent → redesigned** | dictionary loop + `EXECUTE IMMEDIATE` → `DROP … IF EXISTS` with `FOREIGN_KEY_CHECKS=0` | `USER_TABLES/USER_SEQUENCES/USER_OBJECTS` do not exist (D2) and `CASCADE CONSTRAINTS PURGE` is not supported (D1). `EXECUTE IMMEDIATE` itself works (P15), but the loop is not needed: MariaDB has `IF EXISTS`. | yes: rerunnable, run before every verification case |
| 04_data.sql (55 INSERT, 4 UPDATE, COMMIT) | data | unchanged | none (header comment only) | `DATE 'yyyy-mm-dd'` literals and doubled quotes (`O''Reilly`) supported (F13) | yes: fines 25.00 and 10.00 created by triggers, as the comments predict |
| Q1–Q6, Q8–Q10, Q12–Q14 | query | unchanged | none | `FETCH FIRST n ROWS ONLY` (F10), derived table without alias (F11), `RANK() OVER` (F12), UNION, EXISTS, all supported | yes: results listed in `probes/migrated_11.8.json` |
| Q7, Q11 | query | unchanged + shim | none | `TRUNC(SYSDATE)` comes from the shim on 11.8; native on 13.0 | yes |
| D1 | PL/SQL block | rewritten | named notation `issue_book(p_book_id => 4, …)` → positional `issue_book(4, 2, 1, v_loan_id)` | `=>` not supported on 11.8 or 13.0 (P2) | yes: "Issued, loan id = 9" |
| D2–D7 | PL/SQL block | unchanged + shim | none | `DBMS_OUTPUT.PUT_LINE` from the shim. Nested blocks, `WHEN OTHERS`, `SQLERRM`, `%TYPE`, explicit cursor FOR loop all work (P11, P13, P16, T11). | yes: same messages as Oracle, incl. `ORA-20001: …` text |
| SET LINESIZE / PAGESIZE / SERVEROUTPUT | SQL*Plus | removed | — | client formatting commands, not SQL | n/a |
| run_all.sql | SQL*Plus | **no equivalent → redesigned** | `@@file` → `migration/tools/run_objects.py`, which splits on SQL*Plus `/` rules | the `mariadb` client has no `/` terminator or `@@`. Keeping `/` means the two corpus folders diff cleanly. | yes |

### The compatibility layer (`corpus/mariadb/lms/00_compat.sql`)

| Shim | Replaces | Fidelity | Remove when |
|---|---|---|---|
| `raise_application_error(code, msg)` | Oracle built-in (P7: missing on 11.8 and 13.0) | `SIGNAL SQLSTATE '45000'` with error number `ABS(code)`. The message is prefixed `ORA-200xx: `, so `SQLERRM` matches Oracle and so does the first line of client error text (Oracle adds `ORA-06512` stack lines after it). **Difference:** `SQLCODE` is `+20001`, not `-20001`, because MariaDB error numbers are positive. | built-in appears |
| `trunc(date)` | `TRUNC(date)` (F1: missing on 11.8) | exact for DATE input. TRUNC(number) is not provided. Does **not** fix `TRUNC(a) - TRUNC(b)`. | MariaDB ≥ 13.0 (native, F1) |
| package `dbms_output.put_line` | `DBMS_OUTPUT` (P17: missing on 11.8 and 13.0) | each line comes back immediately as a result set. Oracle buffers lines until the call ends and needs `SERVEROUTPUT ON`. | never (no built-in planned) |

## Feature matrix (reusable for other code bases)

Probe IDs refer to [`tools/probe_features.py`](tools/probe_features.py). Raw output: `probes/features_oracle_mode*.md`. ✅ works · ❌ error · ⚠️ **runs but returns a different result** (the dangerous kind).

| Feature | 11.8 | 13.0 | Bucket | Workaround | Probe |
|---|---|---|---|---|---|
| VARCHAR2, NUMBER(p,s), DATE, CHAR types | ✅ | ✅ | unchanged | DATE becomes DATETIME. NUMBER without precision becomes **DOUBLE** (see ⚠️ below). | T1 |
| `NUMBER` variable arithmetic | ⚠️ | ⚠️ | change | `0.1 + 0.2 = 0.3` is false because NUMBER is DOUBLE. Declare money as `NUMBER(p,s)`. | N14, N15 |
| `%TYPE`, `%ROWTYPE`, `TYPE … IS RECORD` | ✅ | ✅ | unchanged | | T11, T12, X6 |
| `CONSTANT` | ❌ | ❌ | change | drop the keyword | T10 |
| `DEFAULT seq.NEXTVAL`, `seq.CURRVAL`, sequences | ✅ | ✅ | unchanged | | T2, P6c |
| `DEFAULT SYSDATE` | ✅ | ✅ | unchanged | | T3 |
| `DEFAULT TRUNC(SYSDATE)` / `USER` / `SYSTIMESTAMP` | ❌ | ✅ / ❌ / ❌ | change | `CURRENT_DATE`, `SUBSTRING_INDEX(USER(),'@',1)`, `CURRENT_TIMESTAMP(6)` | T4–T7 |
| Function-based index | ❌ | ❌ | change | invisible virtual column + index | T8 |
| `TRUNC(date)` | ❌ | ✅ | change | shim, or `CAST(x AS DATE)` | F1 |
| **`DATE - DATE`** | ⚠️ | ⚠️ | change | `DATEDIFF(a, b)`. Correct only for two literals in the same month; otherwise a YYYYMMDDhhmmss difference. | F2, F2b |
| **`DATE + n`** | ⚠️ | ⚠️ | change | `ADDDATE(d, n)` or `d + INTERVAL n DAY`. A literal gives the number `20261034`; a variable gets **n seconds** added. | F3, F3b |
| NVL, NVL2, DECODE, `||`, CASE, SUBSTR(−n), ADD_MONTHS, TO_CHAR(date) | ✅ | ✅ | unchanged | | F4–F7, X16, X16c, X17, X17b |
| TO_DATE, MONTHS_BETWEEN | ❌ | ✅ | change | `STR_TO_DATE`, `TIMESTAMPDIFF(MONTH, …)` | X16b, X16d |
| INSTR with 4 arguments | ❌ | ❌ | change | loop or `SUBSTRING_INDEX` | X17c |
| `LISTAGG … WITHIN GROUP` | ❌ | ❌ | change | `GROUP_CONCAT(x ORDER BY x SEPARATOR ', ')` | F9, F9b |
| `FETCH FIRST n ROWS`, ROWNUM, MINUS, derived table without alias, window functions | ✅ | ✅ | unchanged | | F10–F12, X13, X15 |
| `(+)` outer join | ❌ | ✅ | change | ANSI `LEFT JOIN` | X14 |
| CONNECT BY | ❌ | ❌ | change | `WITH RECURSIVE` (verified same rows) | X1, X1b |
| MERGE | ❌ | ❌ | change | `INSERT … ON DUPLICATE KEY UPDATE` (needs a unique key) | X2, X2b |
| PIVOT | ❌ | ❌ | change | `SUM(CASE …)` per column | X23 |
| IN/OUT params, positional calls, param DEFAULT | ✅ | ✅ | unchanged | | P1, P3 |
| Named notation `p(a => 1)` | ❌ | ❌ | change | positional call | P2 |
| `SELECT … INTO … FOR UPDATE` | ✅ | ✅ | unchanged | lock lasts to COMMIT **only with autocommit=0** | P5 |
| `INSERT … RETURNING … INTO` | ❌ | ❌ | change | `seq.CURRVAL` after insert; plain-SQL `RETURNING` exists (P6b) | P6, P6b |
| `RAISE_APPLICATION_ERROR` | ❌ | ❌ | no equivalent → shim | `SIGNAL` (shim) | P7, P7b |
| `SQL%ROWCOUNT`, NO_DATA_FOUND, TOO_MANY_ROWS, WHEN OTHERS, RAISE, SQLERRM, user exceptions | ✅ | ✅ | unchanged | `SQLCODE` numbers are MariaDB's | P8–P11, X9, X21 |
| `PRAGMA EXCEPTION_INIT` | ❌ | ❌ | change | `WHEN OTHERS THEN IF SQLCODE = <MariaDB errno> …` (MariaDB error numbers, not ORA codes) | X10 |
| COMMIT/ROLLBACK in procedures | ⚠️ | ⚠️ | unchanged + setting | ROLLBACK undoes nothing with autocommit=1 (P12) | P12 |
| Explicit cursors, cursor FOR loops, OPEN/FETCH/CLOSE, `%NOTFOUND`, GOTO | ✅ | ✅ | unchanged | | P13, P14, X11, X20 |
| `EXECUTE IMMEDIATE` | ✅ | ✅ | unchanged | | P15 |
| Packages (spec + body, package state) | ✅ | ✅ | unchanged | | X8 |
| `SYS_REFCURSOR` | ❌ | ✅ (CREATE accepted; fetching not probed) | change | return a result set from the procedure | X12 |
| Associative arrays `INDEX BY` | ❌ | ✅ (INTEGER/VARCHAR2 keys; not PLS_INTEGER) | change | temporary table | X5–X5c |
| BULK COLLECT, FORALL | ❌ | ❌ | no equivalent | set-based SQL or a cursor loop | X3, X4 |
| `PRAGMA AUTONOMOUS_TRANSACTION` | ❌ | ❌ | no equivalent | redesign: a second connection, or log outside the transaction | X7 |
| `CREATE TYPE … AS OBJECT` | ❌ | ❌ | no equivalent | redesign as tables/JSON | X19 |
| DBMS_OUTPUT, UTL_FILE | ❌ | ❌ | no equivalent | shim (DBMS_OUTPUT); move file I/O to the application (UTL_FILE) | P17, X18 |
| Row triggers with `:NEW/:OLD`, DECLARE in trigger, `UPDATE OF col` | ✅ | ✅ | unchanged | | R1, R3, R6, R7 |
| Trigger `WHEN (…)` | ❌ | ❌ | change | `IF` in the body | R2 |
| Multi-event trigger, `INSERTING/UPDATING` | ❌ | ✅ | change | one trigger per event | R4, R5 |
| Statement-level trigger | ❌ | ❌ | no equivalent | row trigger, or move to the procedure | X22 |
| `USER_TABLES` etc., `CASCADE CONSTRAINTS PURGE` | ❌ | ❌ | no equivalent | `information_schema`, `DROP … IF EXISTS` | D1, D2 |
| `'' IS NULL` and other empty-string rules | ⚠️ | ⚠️ | setting | `EMPTY_STRING_IS_NULL` (13/13 probes then match) | N1–N13 |
| String comparison (case, trailing blanks) | ⚠️ | ⚠️ | setting | collation `utf8mb4_nopad_bin` | [SILENT_DIFFERENCES](SILENT_DIFFERENCES.md#4-string-comparison-collation) |

## Notes for the team

- **Inherited bug in the corpus** (same on Oracle): `V_MEMBER_SUMMARY` reports `open_loans = 1` for a member with no loans. The LEFT JOIN row has `return_date IS NULL`. The fix is `COUNT(CASE WHEN l.loan_id IS NOT NULL AND l.return_date IS NULL THEN 1 END)`. It is left unfixed in both folders so the migration diff stays clean, and is pinned by a verification case.
- **For the harness (Person 3):** Q5 (`FETCH FIRST 3`) has ties at `times_borrowed = 1`, and Q9 has no `ORDER BY`, so row order and the tie-break are not deterministic on either database. Sort before comparing, and compare Q5 as a multiset of counts. NUMBER-without-precision values come back as `1.0`/`125.0` from MariaDB, so normalise numbers. Error codes: Oracle `-20001` ↔ MariaDB `20001`.
- **For the environment (Person 1):** mount [`mariadb-oracle.cnf`](mariadb-oracle.cnf) so every connection gets the four settings without the application having to set them. It was tested: a new container reports the expected `sql_mode`, `autocommit=0` and `utf8mb4_nopad_bin`.
