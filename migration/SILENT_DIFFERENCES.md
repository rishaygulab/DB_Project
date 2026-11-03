# Silent differences: Oracle vs MariaDB `sql_mode=ORACLE`

These differences raise **no error**. The code compiles, runs and returns a plausible but different answer, which is what migration teams fear most. Every claim below comes from a probe in [`tools/probe_features.py`](tools/probe_features.py) or a case in [`verify/cases.json`](verify/cases.json), run on MariaDB 11.8.9 and 13.0.2. Both versions behave the same on everything in this file.

**Measured impact on this corpus:** the migrated code passes **62/62** verification cases with the recommended settings. With only `SET sql_mode=ORACLE` (default collation, autocommit on), **7 cases return wrong results and none of them raises an error**:

| Case | Oracle | `sql_mode=ORACLE` alone | Fixed by |
|---|---|---|---|
| `fn_loan_days('student')` | 7 | **14** | collation |
| `fn_loan_days('STUDENT ')` | 7 | **14** | collation |
| insert member with `first_name = ''` | ORA-01400, rejected | **accepted** | `EMPTY_STRING_IS_NULL` |
| insert member with `phone = ''`, then `phone IS NULL` | 1 row | **0 rows** | `EMPTY_STRING_IS_NULL` |
| insert `member_type = 'student'` | ORA-02290 CHECK violated | **accepted** | collation |
| emails `a@x` and `A@x` | both allowed | **duplicate key** | collation |
| `amount / 0` | ORA-01476 divisor is zero | NULL (then a CHECK error) | `ERROR_FOR_DIVISION_BY_ZERO` |

Reproduce:

```sh
.venv/bin/python migration/tools/verify_objects.py                                                  # 62/62
.venv/bin/python migration/tools/verify_objects.py --sql-mode ORACLE --collation default --autocommit 1   # 55/62
```

## Recommended settings

```ini
# migration/mariadb-oracle.cnf  (or the SET SESSION equivalents on every connection)
sql_mode = ORACLE,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,EMPTY_STRING_IS_NULL
autocommit = 0
collation_server = utf8mb4_nopad_bin
```

Routines store the `sql_mode` they were **created** with, but tables, literals and inserts follow the **caller's** session. So the application's connections need these settings too, not only the load script. Setting them in the server config covers both.

---

## 1. NULL and the empty string

In Oracle, `''` **is** NULL: a zero-length VARCHAR2 is stored and compared as NULL. MariaDB keeps them distinct by default, and **`sql_mode=ORACLE` does not change that**. The separate flag `EMPTY_STRING_IS_NULL` does.

| Probe | Expression | Oracle | `ORACLE` | `ORACLE,EMPTY_STRING_IS_NULL` |
|---|---|---|---|---|
| N1 | `'' IS NULL` | true | **false** | true |
| N2 | `NVL('', 'x')` | `x` | **`''`** | `x` |
| N3 | `LENGTH('')` | NULL | **0** | NULL |
| N4 | insert `''` into `NOT NULL` column | error ORA-01400 | **accepted** | error 1048 |
| N5 | insert `''`, then `WHERE col IS NULL` | 1 row | **0 rows** | 1 row |
| N8 | `'' = ''` | not true (NULL = NULL) | **true** | not true |
| N9 | PL/SQL `v VARCHAR2(10) := ''`, then `v IS NULL` | true | **false** | true |
| N10 | procedure parameter passed `''`, then `IS NULL` | true | **false** | true |
| N12 | `COUNT(col)` over `''`, `'x'`, NULL | 1 | **2** | 1 |
| N6 | `'a' \|\| NULL \|\| 'b'` | `ab` | `ab` | `ab` |
| N7 | `CONCAT('a', NULL)` | `a` | `a` | `a` |
| N11 | `CASE t WHEN 'STUDENT' … ELSE 7` with `''` | 7 | 7 | 7 |
| N13 | `TRIM('  ') IS NULL` | true | true | true |

**What `sql_mode=ORACLE` covers on its own:** NULL-tolerant concatenation (`||` and `CONCAT` ignore NULL, N6 and N7) and `TRIM` returning NULL for an all-blank result (N13). **What needs `EMPTY_STRING_IS_NULL`:** everything that stores, compares or measures an empty string (N1–N5, N8–N10, N12). With the flag on, all 13 probes match Oracle.

**Where this would bite in this corpus:** `members.phone` is nullable. An application that sends `''` for "no phone" stores NULL on Oracle, but without the flag it stores `''` on MariaDB, and reports that filter `WHERE phone IS NULL` then miss those rows. The `NOT NULL` name columns would accept `''` instead of rejecting it.

**Caveat:** the flag converts `''` *literals and values coming in*. Data that already holds `''`, for example from a CSV import done without the flag, stays `''`, and is then neither `IS NULL` nor `= ''`, because the literal `''` itself becomes NULL. Find such rows with `WHERE LENGTH(col) = 0` (tested: `IS NULL` → 0 rows, `= ''` → 0 rows, `LENGTH(col) = 0` → 1 row) and `UPDATE … SET col = NULL` them.

## 2. Date arithmetic

In Oracle mode `DATE` becomes `DATETIME` (probe T1), and arithmetic on it is not day-based:

| Probe | Expression | Oracle | MariaDB |
|---|---|---|---|
| F2 | `DATE'2026-09-20' - DATE'2026-09-15'` | 5 | 5 (correct by coincidence: `20260920 - 20260915`) |
| follow-up | `DATE'2026-10-04' - DATE'2026-09-28'` | 6 | **76** |
| F2b | `a - b` on DATE **variables**, 5 days apart | 5 | **5000000** |
| F2b | same, 6 days across a month | 6 | **76000000** |
| F3 | `DATE'2026-10-20' + 14` | 2026-11-03 | **20261034** (a number) |
| F3b | `d + 14` on a DATE **variable** | 2026-11-03 | **2026-10-20 00:00:14** (14 seconds) |

The first case is the trap: a quick test with dates in the same month passes. Unmigrated, `fn_calc_fine` charges **25,000,000** for a 5-day-late book, and `TRUNC(SYSDATE) + 14` in `issue_book` stores a due date of **today 00:00:14** (both tested with the original source plus the `TRUNC` shim). **Rewrite all date arithmetic:**

| Oracle | MariaDB |
|---|---|
| `TRUNC(a) - TRUNC(b)` | `DATEDIFF(a, b)` (ignores the time part, like TRUNC) |
| `d + n` | `ADDDATE(d, n)` or `d + INTERVAL n DAY` |
| `d - n` | `SUBDATE(d, n)` |
| `a - b` with time, fractional days | `TIMESTAMPDIFF(SECOND, b, a) / 86400` |

Search a codebase with `grep -nE "(SYSDATE|_date|DATE '[^']*')\)?\s*[-+]" *.sql`. On `corpus/oracle/lms` it finds exactly the 3 sites rewritten here. Adjust `_date` to your column naming.

## 3. Transactions: autocommit

Oracle has no autocommit. A procedure's work stays pending until COMMIT, ROLLBACK undoes it, and `SELECT … FOR UPDATE` holds the row lock until the transaction ends. MariaDB starts sessions with `autocommit=1`, and `SET sql_mode=ORACLE` does not change it:

| Probe | Procedure | Oracle | autocommit=1 | autocommit=0 |
|---|---|---|---|---|
| P12 | `INSERT 1; ROLLBACK; INSERT 2; COMMIT` | rows: 2 | **rows: 1, 2** | rows: 2 |

For `issue_book`, autocommit=1 means the `FOR UPDATE` lock on the book row is released as soon as that SELECT finishes. The comment "lock the book row so two staff can't lend the last copy at once" is then no longer true. The `CHECK (available_copies BETWEEN 0 AND total_copies)` would still stop stock going negative, but the caller would get a constraint error instead of `-20002 No copies available`.

## 4. String comparison (collation)

Oracle compares VARCHAR2 **binary** (case-sensitive) and **without blank padding**. MariaDB 11.8's default collation `utf8mb4_uca1400_ai_ci` is case- *and accent-*insensitive and pads trailing blanks. That changes PL/SQL `CASE`/`IF`, CHECK constraints and UNIQUE keys:

| Check | Oracle | `uca1400_ai_ci` (default) | `utf8mb4_bin` | `utf8mb4_nopad_bin` |
|---|---|---|---|---|
| `fn_loan_days('student')` | 7 | **14** | 7 | 7 |
| `fn_loan_days('STUDENT ')` | 7 | **14** | **14** | 7 |
| UNIQUE: `A@x.com` then `a@x.com` | accepted | **rejected** | accepted | accepted |
| CHECK `IN ('STUDENT')` with `'student'` | rejected | **accepted** | rejected | rejected |
| UNIQUE: `A@x.com` then `A@x.com ` | accepted | **rejected** | **rejected** | accepted |
| `WHERE email = 'A@X.COM'` | 0 rows | **1 row** | 0 | 0 |

Only `utf8mb4_nopad_bin` matches all six. Set it when you **create the database**, because existing tables keep their collation. If the application has come to rely on case-insensitive search, that was never Oracle behaviour; on Oracle it would use `UPPER()`, which is why `ix_books_title` exists.

## 5. Strict mode and division by zero

The server default is `STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,…`, but `SET sql_mode=ORACLE` **replaces** the whole value with `PIPES_AS_CONCAT,ANSI_QUOTES,IGNORE_SPACE,ORACLE,NO_KEY_OPTIONS,NO_TABLE_OPTIONS,NO_FIELD_OPTIONS,NO_AUTO_CREATE_USER,SIMULTANEOUS_ASSIGNMENT`. Strict mode is gone, so:

- `1/0` returns NULL with a warning. Oracle raises ORA-01476. In PL/SQL, a block that relies on `WHEN ZERO_DIVIDE` or `WHEN OTHERS` silently continues (probe P16).
- Values too long for a column are truncated with a warning instead of rejected (tested: `'abcdef'` into `VARCHAR2(3)` stores `'abc'`, warning 1265). Oracle raises ORA-12899.

Always write `sql_mode` as a full list, as in the recommended settings above.

## 6. NUMBER without precision is DOUBLE

`NUMBER` with no `(p,s)` maps to `DOUBLE` (probe T1), so it is binary floating point, not Oracle's exact decimal:

| Probe | Declaration | `a + b = 0.3` with 0.1 and 0.2 |
|---|---|---|
| N14 | `a NUMBER` | **NOT equal** |
| N15 | `a NUMBER(10,2)` | equal |

In this corpus it shows up as `1.0` / `125.0` in output. The money values are whole numbers and only compared with `> 0`, so no result is wrong, which is why the code was left as is. For money in other code, declare `NUMBER(p,s)`. For keys, `DOUBLE` is exact up to 2^53.

## 7. Error codes and messages

| | Oracle | MariaDB (with `00_compat.sql` shim) |
|---|---|---|
| `SQLCODE` after `RAISE_APPLICATION_ERROR(-20001, …)` | −20001 | **20001** |
| `SQLERRM` | `ORA-20001: Member is suspended.` | `ORA-20001: Member is suspended.` (the shim adds the prefix) |
| Built-in errors (duplicate key, NOT NULL, CHECK) | ORA-00001 / 01400 / 02290 | 1062 / 1048 / 4025 |

Code that tests `SQLCODE = -20001`, or `-1` for a duplicate key, must be updated. Named exceptions are mapped correctly: `NO_DATA_FOUND` (P9), `TOO_MANY_ROWS` (X21) and `DUP_VAL_ON_INDEX` (tested) are all caught by name.
