#!/usr/bin/env python3
"""Isolated feature probes: one small script per Oracle feature used by the corpus.

Each probe runs in a throwaway database under the given sql_mode and records
what MariaDB returned next to what Oracle documents for the same input. The
Oracle column is documented behaviour; the Oracle reference instance (Person 1)
and the harness (Person 3) confirm it.

Usage: probe_features.py [--extra-mode EMPTY_STRING_IS_NULL] [--json out.json] [--md out.md]
"""
import argparse
import json
import os
import subprocess

# (id, feature, used_in, script, oracle_expected)
# Scripts use '$$' as the statement delimiter.
PROBES = [
    # ---------------- types and declarations ----------------
    ("T1", "VARCHAR2 / NUMBER(p,s) / DATE / CHAR column types", "all tables",
     "CREATE TABLE t (a VARCHAR2(10), b NUMBER(8,2), c DATE, d CHAR(1), e NUMBER)$$"
     "SELECT column_name, column_type FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='t' ORDER BY ordinal_position$$",
     "table created"),
    ("T2", "DEFAULT seq.NEXTVAL on a column", "all tables",
     "CREATE SEQUENCE s START WITH 1 INCREMENT BY 1 NOCACHE$$"
     "CREATE TABLE t (id NUMBER DEFAULT s.NEXTVAL PRIMARY KEY, x VARCHAR2(5))$$"
     "INSERT INTO t (x) VALUES ('a')$$INSERT INTO t (x) VALUES ('b')$$SELECT id, x FROM t ORDER BY id$$",
     "1 a / 2 b"),
    ("T3", "DEFAULT SYSDATE", "members.join_date",
     "CREATE TABLE t (d DATE DEFAULT SYSDATE NOT NULL, x NUMBER)$$INSERT INTO t (x) VALUES (1)$$SELECT d IS NOT NULL FROM t$$",
     "row inserted with current date"),
    ("T4", "DEFAULT TRUNC(SYSDATE)", "loans.loan_date",
     "CREATE TABLE t (d DATE DEFAULT TRUNC(SYSDATE) NOT NULL, x NUMBER)$$",
     "table created"),
    ("T5", "DEFAULT USER", "book_audit.changed_by",
     "CREATE TABLE t (u VARCHAR2(30) DEFAULT USER NOT NULL, x NUMBER)$$",
     "table created"),
    ("T6", "DEFAULT SYSTIMESTAMP", "book_audit.changed_at",
     "CREATE TABLE t (ts TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL, x NUMBER)$$",
     "table created"),
    ("T7", "DEFAULT USER() (MariaDB spelling)", "book_audit.changed_by",
     "CREATE TABLE t (u VARCHAR2(80) DEFAULT USER() NOT NULL, ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, x NUMBER)$$"
     "INSERT INTO t (x) VALUES (1)$$SELECT u FROM t$$",
     "n/a (rewrite target)"),
    ("T8", "Function-based index ON t(UPPER(col))", "ix_books_title",
     "CREATE TABLE t (title VARCHAR2(200))$$CREATE INDEX ix ON t(UPPER(title))$$",
     "index created"),
    ("T9", "CHECK constraints incl. LIKE pattern", "members, books, loans, fines",
     "CREATE TABLE t (e VARCHAR2(50), CONSTRAINT ck CHECK (e LIKE '%_@_%._%'))$$INSERT INTO t VALUES ('bad')$$",
     "ORA-02290 check constraint violated"),
    ("T10", "CONSTANT in declaration section", "fn_calc_fine",
     "CREATE FUNCTION f RETURN NUMBER IS c CONSTANT NUMBER := 5; BEGIN RETURN c; END;$$SELECT f() FROM DUAL$$",
     "5"),
    ("T11", "%TYPE anchored variables", "issue_book",
     "CREATE TABLE t (a VARCHAR2(10))$$INSERT INTO t VALUES ('x')$$"
     "CREATE PROCEDURE p(o OUT VARCHAR2) IS v t.a%TYPE; BEGIN SELECT a INTO v FROM t; o := v; END;$$"
     "DECLARE r VARCHAR2(10); BEGIN p(r); SELECT r FROM DUAL; END;$$",
     "x"),
    ("T12", "%ROWTYPE record", "(guide example)",
     "CREATE TABLE t (a NUMBER, b VARCHAR2(5))$$INSERT INTO t VALUES (1,'q')$$"
     "DECLARE r t%ROWTYPE; BEGIN SELECT * INTO r FROM t; SELECT r.a, r.b FROM DUAL; END;$$",
     "1 q"),
    # ---------------- functions / expressions ----------------
    ("F1", "TRUNC(date)", "fn_calc_fine, issue_book, views",
     "SELECT TRUNC(TIMESTAMP'2026-09-20 15:30:00') FROM DUAL$$",
     "2026-09-20 00:00:00"),
    ("F2", "DATE - DATE gives days", "fn_calc_fine, v_overdue_loans",
     "SELECT DATE'2026-09-20' - DATE'2026-09-15' FROM DUAL$$",
     "5"),
    ("F2b", "DATE - DATE on DATE-typed variables", "fn_calc_fine",
     "CREATE FUNCTION f(a DATE, b DATE) RETURN NUMBER IS BEGIN RETURN a - b; END;$$"
     "SELECT f(DATE'2026-09-20', DATE'2026-09-15') AS same_month, f(DATE'2026-10-04', DATE'2026-09-28') AS across_month FROM DUAL$$",
     "5 / 6"),
    ("F2c", "DATEDIFF(a,b) (rewrite target)", "fn_calc_fine",
     "SELECT DATEDIFF(DATE'2026-10-04', DATE'2026-09-28') FROM DUAL$$",
     "n/a (rewrite target)"),
    ("F3", "DATE + n adds days", "issue_book",
     "SELECT DATE'2026-10-20' + 14 FROM DUAL$$",
     "2026-11-03"),
    ("F3b", "DATE + n on a DATE variable", "issue_book",
     "CREATE FUNCTION f(a DATE) RETURN DATE IS BEGIN RETURN a + 14; END;$$SELECT f(DATE'2026-10-20') FROM DUAL$$",
     "2026-11-03"),
    ("F4", "NVL", "fn_member_dues",
     "SELECT NVL(NULL, 0), NVL(3, 0) FROM DUAL$$", "0 3"),
    ("F5", "DECODE", "(guide example)",
     "SELECT DECODE(2, 1,'one', 2,'two', 'other'), DECODE(NULL, NULL,'null-match','no') FROM DUAL$$",
     "two null-match"),
    ("F6", "|| string concatenation", "views, issue_book",
     "SELECT 'a' || 'b' || 1 FROM DUAL$$", "ab1"),
    ("F7", "CASE expression in PL/SQL RETURN", "fn_loan_days",
     "CREATE FUNCTION f(t VARCHAR2) RETURN NUMBER IS BEGIN RETURN CASE t WHEN 'A' THEN 1 ELSE 2 END; END;$$SELECT f('A'), f('Z') FROM DUAL$$",
     "1 2"),
    ("F8", "SYSDATE / DUAL", "everywhere",
     "SELECT SYSDATE IS NOT NULL FROM DUAL$$", "1"),
    ("F9", "LISTAGG(x, ', ') WITHIN GROUP (ORDER BY x)", "v_book_catalog",
     "CREATE TABLE t (g NUMBER, n VARCHAR2(10))$$INSERT INTO t VALUES (1,'b'),(1,'a')$$"
     "SELECT g, LISTAGG(n, ', ') WITHIN GROUP (ORDER BY n) FROM t GROUP BY g$$",
     "1 a, b"),
    ("F9b", "GROUP_CONCAT(x ORDER BY x SEPARATOR ', ') (rewrite target)", "v_book_catalog",
     "CREATE TABLE t (g NUMBER, n VARCHAR2(10))$$INSERT INTO t VALUES (1,'b'),(1,'a'),(2,NULL)$$"
     "SELECT g, GROUP_CONCAT(n ORDER BY n SEPARATOR ', ') FROM t GROUP BY g ORDER BY g$$",
     "n/a (rewrite target)"),
    ("F10", "FETCH FIRST n ROWS ONLY", "Q5",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2),(3),(4)$$SELECT a FROM t ORDER BY a DESC FETCH FIRST 3 ROWS ONLY$$",
     "4 3 2"),
    ("F11", "Derived table without alias", "Q9",
     "SELECT x FROM (SELECT 1 AS x FROM DUAL)$$", "1"),
    ("F12", "RANK() OVER (PARTITION BY ...)", "Q9",
     "CREATE TABLE t (c VARCHAR2(5), n NUMBER)$$INSERT INTO t VALUES ('a',5),('a',3),('b',1)$$"
     "SELECT c, n, RANK() OVER (PARTITION BY c ORDER BY n DESC) FROM t ORDER BY c, n DESC$$",
     "a 5 1 / a 3 2 / b 1 1"),
    ("F13", "DATE 'yyyy-mm-dd' literal", "04_data",
     "SELECT DATE '2026-08-01' FROM DUAL$$", "2026-08-01"),
    # ---------------- PL/SQL statements ----------------
    ("P1", "IN / OUT parameters, positional call", "issue_book",
     "CREATE PROCEDURE p(a IN NUMBER, b OUT NUMBER) IS BEGIN b := a * 2; END;$$"
     "DECLARE r NUMBER; BEGIN p(21, r); SELECT r FROM DUAL; END;$$", "42"),
    ("P2", "Named parameter call  p(a => 1)", "D1 demo",
     "CREATE PROCEDURE p(a IN NUMBER, b OUT NUMBER) IS BEGIN b := a * 2; END;$$"
     "DECLARE r NUMBER; BEGIN p(a => 21, b => r); SELECT r FROM DUAL; END;$$", "42"),
    ("P3", "Parameter DEFAULT value, omitted in call", "return_book",
     "CREATE PROCEDURE p(a IN NUMBER, b IN NUMBER DEFAULT 10) IS BEGIN SELECT a + b FROM DUAL; END;$$"
     "BEGIN p(1); END;$$", "11"),
    ("P4", "Parameter DEFAULT TRUNC(SYSDATE)", "return_book",
     "CREATE PROCEDURE p(d IN DATE DEFAULT TRUNC(SYSDATE)) IS BEGIN SELECT d FROM DUAL; END;$$BEGIN p(); END;$$",
     "today 00:00:00"),
    ("P5", "SELECT ... INTO ... FOR UPDATE", "issue_book",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (7)$$"
     "DECLARE v NUMBER; BEGIN SELECT a INTO v FROM t FOR UPDATE; SELECT v FROM DUAL; END;$$", "7"),
    ("P6", "INSERT ... RETURNING col INTO var", "issue_book",
     "CREATE SEQUENCE s$$CREATE TABLE t (id NUMBER DEFAULT s.NEXTVAL, x NUMBER)$$"
     "DECLARE v NUMBER; BEGIN INSERT INTO t (x) VALUES (1) RETURNING id INTO v; SELECT v FROM DUAL; END;$$",
     "1"),
    ("P6b", "INSERT ... RETURNING col (no INTO, MariaDB form)", "issue_book",
     "CREATE SEQUENCE s$$CREATE TABLE t (id NUMBER DEFAULT s.NEXTVAL, x NUMBER)$$INSERT INTO t (x) VALUES (1) RETURNING id$$",
     "n/a"),
    ("P6c", "seq.CURRVAL after insert (rewrite target)", "issue_book",
     "CREATE SEQUENCE s$$CREATE TABLE t (id NUMBER DEFAULT s.NEXTVAL, x NUMBER)$$"
     "DECLARE v NUMBER; BEGIN INSERT INTO t (x) VALUES (1); INSERT INTO t (x) VALUES (2); v := s.CURRVAL; SELECT v FROM DUAL; END;$$",
     "n/a (rewrite target)"),
    ("P7", "RAISE_APPLICATION_ERROR(-20001, msg)", "issue_book, return_book, pay_fine",
     "BEGIN RAISE_APPLICATION_ERROR(-20001, 'Member is suspended.'); END;$$",
     "ORA-20001: Member is suspended."),
    ("P7b", "SIGNAL SQLSTATE (rewrite target)", "issue_book",
     "BEGIN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 20001, MESSAGE_TEXT = 'Member is suspended.'; END;$$",
     "n/a (rewrite target)"),
    ("P8", "SQL%ROWCOUNT after UPDATE", "return_book, pay_fine",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(1),(2)$$"
     "BEGIN UPDATE t SET a = 9 WHERE a = 1; SELECT SQL%ROWCOUNT FROM DUAL; END;$$", "2"),
    ("P9", "EXCEPTION WHEN NO_DATA_FOUND", "issue_book",
     "CREATE TABLE t (a NUMBER)$$"
     "DECLARE v NUMBER; BEGIN SELECT a INTO v FROM t; EXCEPTION WHEN NO_DATA_FOUND THEN SELECT 'caught' FROM DUAL; END;$$",
     "caught"),
    ("P10", "WHEN OTHERS ... RAISE (re-raise)", "issue_book",
     "BEGIN BEGIN RAISE_APPLICATION_ERROR(-20009,'inner'); EXCEPTION WHEN OTHERS THEN RAISE; END; END;$$",
     "ORA-20009: inner"),
    ("P11", "SQLERRM in handler", "D2-D5 demos",
     "BEGIN RAISE_APPLICATION_ERROR(-20002,'No copies available.'); EXCEPTION WHEN OTHERS THEN SELECT SQLCODE, SQLERRM FROM DUAL; END;$$",
     "-20002 ORA-20002: No copies available."),
    ("P12", "COMMIT / ROLLBACK inside procedure", "issue_book, return_book, pay_fine",
     "CREATE TABLE t (a NUMBER)$$CREATE PROCEDURE p IS BEGIN INSERT INTO t VALUES (1); ROLLBACK; INSERT INTO t VALUES (2); COMMIT; END;$$"
     "BEGIN p(); END;$$SELECT a FROM t$$", "2"),
    ("P13", "Explicit CURSOR + cursor FOR loop", "D7 demo",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2)$$"
     "DECLARE CURSOR c IS SELECT a FROM t ORDER BY a; s NUMBER := 0; BEGIN FOR r IN c LOOP s := s + r.a; END LOOP; SELECT s FROM DUAL; END;$$",
     "3"),
    ("P14", "Implicit cursor FOR loop  FOR r IN (SELECT ...)", "01_drop",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2)$$"
     "DECLARE s NUMBER := 0; BEGIN FOR r IN (SELECT a FROM t) LOOP s := s + r.a; END LOOP; SELECT s FROM DUAL; END;$$",
     "3"),
    ("P15", "EXECUTE IMMEDIATE dynamic DDL", "01_drop",
     "CREATE TABLE t (a NUMBER)$$BEGIN EXECUTE IMMEDIATE 'DROP TABLE ' || 't'; END;$$", "table dropped"),
    ("P16", "Nested block with outer EXCEPTION", "D2-D5 demos",
     "BEGIN DECLARE v NUMBER; BEGIN v := 1/0; END; EXCEPTION WHEN OTHERS THEN SELECT 'outer caught' FROM DUAL; END;$$",
     "outer caught (ZERO_DIVIDE)"),
    ("P17", "DBMS_OUTPUT.PUT_LINE", "06_queries demos",
     "BEGIN DBMS_OUTPUT.PUT_LINE('hello'); END;$$", "hello on server output"),
    ("P18", "END name; labelled unit end", "all PL/SQL units",
     "CREATE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END f;$$SELECT f() FROM DUAL$$", "1"),
    ("P19", "Function call without parentheses in SQL", "views (fn_x(...) only)",
     "CREATE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;$$SELECT f FROM DUAL$$", "1"),
    # ---------------- triggers ----------------
    ("R1", "Row trigger with :NEW / :OLD", "all triggers",
     "CREATE TABLE t (a NUMBER)$$CREATE TABLE l (v NUMBER)$$"
     "CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW BEGIN INSERT INTO l VALUES (:NEW.a); END;$$"
     "INSERT INTO t VALUES (5)$$SELECT v FROM l$$", "5"),
    ("R2", "Trigger WHEN (condition) clause", "trg_loans_ai, trg_loans_au_return",
     "CREATE TABLE t (a NUMBER)$$CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW WHEN (NEW.a > 0) BEGIN NULL; END;$$",
     "trigger created"),
    ("R3", "AFTER UPDATE OF column ON t", "trg_loans_au_return, trg_books_audit",
     "CREATE TABLE t (a NUMBER, b NUMBER)$$CREATE TRIGGER tr AFTER UPDATE OF a ON t FOR EACH ROW BEGIN NULL; END;$$",
     "trigger created"),
    ("R4", "Multi-event trigger INSERT OR UPDATE OR DELETE", "trg_books_audit",
     "CREATE TABLE t (a NUMBER)$$CREATE TRIGGER tr AFTER INSERT OR DELETE ON t FOR EACH ROW BEGIN NULL; END;$$",
     "trigger created"),
    ("R5", "INSERTING / UPDATING / DELETING predicates", "trg_books_audit",
     "CREATE TABLE t (a NUMBER)$$CREATE TABLE l (v VARCHAR2(10))$$"
     "CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW BEGIN IF INSERTING THEN INSERT INTO l VALUES ('ins'); END IF; END;$$"
     "INSERT INTO t VALUES (1)$$SELECT v FROM l$$", "ins"),
    ("R6", "DECLARE section inside trigger body", "trg_loans_au_return",
     "CREATE TABLE t (a NUMBER)$$CREATE TABLE l (v NUMBER)$$"
     "CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW DECLARE x NUMBER; BEGIN x := :NEW.a * 2; INSERT INTO l VALUES (x); END;$$"
     "INSERT INTO t VALUES (4)$$SELECT v FROM l$$", "8"),
    ("R7", "Trigger calling a stored function", "trg_loans_au_return",
     "CREATE FUNCTION f(a NUMBER) RETURN NUMBER IS BEGIN RETURN a + 1; END;$$CREATE TABLE t (a NUMBER)$$CREATE TABLE l (v NUMBER)$$"
     "CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW BEGIN INSERT INTO l VALUES (f(:NEW.a)); END;$$"
     "INSERT INTO t VALUES (1)$$SELECT v FROM l$$", "2"),
    # ---------------- DDL / dictionary ----------------
    ("D1", "DROP TABLE ... CASCADE CONSTRAINTS PURGE", "01_drop",
     "CREATE TABLE t (a NUMBER)$$DROP TABLE t CASCADE CONSTRAINTS PURGE$$", "table dropped"),
    ("D2", "user_tables / user_sequences / user_objects views", "01_drop",
     "SELECT table_name FROM user_tables$$", "rows"),
    ("D3", "CREATE OR REPLACE VIEW", "05_views",
     "CREATE OR REPLACE VIEW v AS SELECT 1 AS a FROM DUAL$$SELECT a FROM v$$", "1"),
    # ---------------- NULL / empty string semantics ----------------
    ("N1", "'' IS NULL", "silent trap",
     "SELECT CASE WHEN '' IS NULL THEN 'NULL' ELSE 'NOT NULL' END FROM DUAL$$", "NULL"),
    ("N2", "NVL('', 'x')", "silent trap",
     "SELECT NVL('', 'x') FROM DUAL$$", "x"),
    ("N3", "LENGTH('')", "silent trap",
     "SELECT LENGTH('') IS NULL FROM DUAL$$", "1 (LENGTH is NULL)"),
    ("N4", "'' inserted into NOT NULL VARCHAR2 column", "members.first_name etc.",
     "CREATE TABLE t (a VARCHAR2(5) NOT NULL)$$INSERT INTO t VALUES ('')$$SELECT COUNT(*) FROM t$$",
     "ORA-01400 cannot insert NULL"),
    ("N5", "'' stored in nullable column, then WHERE col IS NULL", "members.phone",
     "CREATE TABLE t (a VARCHAR2(5))$$INSERT INTO t VALUES ('')$$SELECT COUNT(*) FROM t WHERE a IS NULL$$",
     "1"),
    ("N6", "'a' || NULL", "views: first_name || ' ' || last_name",
     "SELECT 'a' || NULL || 'b' FROM DUAL$$", "ab"),
    ("N7", "CONCAT('a', NULL)", "silent trap",
     "SELECT CONCAT('a', NULL) FROM DUAL$$", "a"),
    ("N8", "'' = '' comparison", "silent trap",
     "SELECT CASE WHEN '' = '' THEN 'TRUE' ELSE 'NOT TRUE' END FROM DUAL$$", "NOT TRUE (NULL = NULL)"),
    ("N9", "PL/SQL variable assigned ''", "silent trap",
     "DECLARE v VARCHAR2(10) := ''; BEGIN SELECT CASE WHEN v IS NULL THEN 'NULL' ELSE 'NOT NULL' END FROM DUAL; END;$$",
     "NULL"),
    ("N10", "Procedure parameter passed ''", "issue_book/fn_loan_days callers",
     "CREATE FUNCTION f(p VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN CASE WHEN p IS NULL THEN 'NULL' ELSE 'NOT NULL' END; END;$$"
     "SELECT f('') FROM DUAL$$", "NULL"),
    ("N11", "fn_loan_days('') falls to ELSE", "fn_loan_days",
     "CREATE FUNCTION f(t VARCHAR2) RETURN NUMBER IS BEGIN RETURN CASE t WHEN 'STUDENT' THEN 14 WHEN 'FACULTY' THEN 30 ELSE 7 END; END;$$"
     "SELECT f(''), f(NULL) FROM DUAL$$", "7 7"),
    ("N12", "COUNT(col) / GROUP_CONCAT over '' values", "v_book_catalog, v_member_summary",
     "CREATE TABLE t (a VARCHAR2(5))$$INSERT INTO t VALUES (''),('x'),(NULL)$$SELECT COUNT(a) FROM t$$",
     "1"),
    ("N13", "TRIM('  ') result", "silent trap",
     "SELECT CASE WHEN TRIM('  ') IS NULL THEN 'NULL' ELSE 'NOT NULL' END FROM DUAL$$", "NULL"),
    ("N14", "NUMBER variable arithmetic 0.1 + 0.2 = 0.3", "fn_member_dues (NUMBER -> DOUBLE)",
     "DECLARE a NUMBER := 0.1; b NUMBER := 0.2; BEGIN SELECT CASE WHEN a + b = 0.3 THEN 'equal' ELSE 'NOT equal' END FROM DUAL; END;$$",
     "equal (NUMBER is exact decimal)"),
    ("N15", "NUMBER(10,2) variable arithmetic 0.1 + 0.2 = 0.3", "rewrite target",
     "DECLARE a NUMBER(10,2) := 0.1; b NUMBER(10,2) := 0.2; BEGIN SELECT CASE WHEN a + b = 0.3 THEN 'equal' ELSE 'NOT equal' END FROM DUAL; END;$$",
     "equal"),
    # ---------------- beyond this corpus: common Oracle features in other code bases ----------------
    ("X1", "CONNECT BY hierarchical query", "not in corpus",
     "CREATE TABLE e (id NUMBER, mgr NUMBER)$$INSERT INTO e VALUES (1,NULL),(2,1),(3,2)$$"
     "SELECT id, LEVEL FROM e START WITH mgr IS NULL CONNECT BY PRIOR id = mgr$$", "1 1 / 2 2 / 3 3"),
    ("X1b", "WITH RECURSIVE (rewrite target for CONNECT BY)", "not in corpus",
     "CREATE TABLE e (id NUMBER, mgr NUMBER)$$INSERT INTO e VALUES (1,NULL),(2,1),(3,2)$$"
     "WITH RECURSIVE h (id, lvl) AS (SELECT id, 1 FROM e WHERE mgr IS NULL UNION ALL SELECT e.id, h.lvl + 1 FROM e JOIN h ON e.mgr = h.id) SELECT id, lvl FROM h ORDER BY id$$",
     "n/a (rewrite target)"),
    ("X2", "MERGE INTO ... USING ... WHEN MATCHED", "not in corpus",
     "CREATE TABLE t (id NUMBER PRIMARY KEY, v NUMBER)$$INSERT INTO t VALUES (1,1)$$"
     "MERGE INTO t USING (SELECT 1 AS id, 9 AS v FROM DUAL) s ON (t.id = s.id) WHEN MATCHED THEN UPDATE SET t.v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v)$$SELECT id, v FROM t$$",
     "1 9"),
    ("X2b", "INSERT ... ON DUPLICATE KEY UPDATE (rewrite target for MERGE)", "not in corpus",
     "CREATE TABLE t (id NUMBER PRIMARY KEY, v NUMBER)$$INSERT INTO t VALUES (1,1)$$"
     "INSERT INTO t VALUES (1, 9), (2, 5) ON DUPLICATE KEY UPDATE v = VALUE(v)$$SELECT id, v FROM t ORDER BY id$$",
     "n/a (rewrite target)"),
    ("X3", "SELECT ... BULK COLLECT INTO collection", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2)$$"
     "DECLARE TYPE nt IS TABLE OF NUMBER; v nt; BEGIN SELECT a BULK COLLECT INTO v FROM t; SELECT v.COUNT FROM DUAL; END;$$", "2"),
    ("X4", "FORALL i IN ... INSERT", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$"
     "DECLARE TYPE nt IS TABLE OF NUMBER INDEX BY PLS_INTEGER; v nt; BEGIN v(1) := 1; v(2) := 2; FORALL i IN 1..2 INSERT INTO t VALUES (v(i)); SELECT COUNT(*) FROM t; END;$$",
     "2"),
    ("X5", "Associative array TABLE OF ... INDEX BY", "not in corpus",
     "DECLARE TYPE at IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER; v at; BEGIN v(1) := 'a'; v(5) := 'b'; SELECT v.COUNT, v(5) FROM DUAL; END;$$",
     "2 b"),
    ("X5b", "Associative array INDEX BY INTEGER", "not in corpus",
     "DECLARE TYPE at IS TABLE OF VARCHAR2(10) INDEX BY INTEGER; v at; BEGIN v(1) := 'a'; v(5) := 'b'; SELECT v.COUNT, v(5) FROM DUAL; END;$$",
     "2 b"),
    ("X5c", "Associative array INDEX BY VARCHAR2", "not in corpus",
     "DECLARE TYPE at IS TABLE OF NUMBER INDEX BY VARCHAR2(10); v at; BEGIN v('x') := 1; v('y') := 2; SELECT v.COUNT, v('y') FROM DUAL; END;$$",
     "2 2"),
    ("X6", "TYPE ... IS RECORD", "not in corpus",
     "DECLARE TYPE r IS RECORD (a NUMBER, b VARCHAR2(5)); v r; BEGIN v.a := 1; v.b := 'x'; SELECT v.a, v.b FROM DUAL; END;$$",
     "1 x"),
    ("X7", "PRAGMA AUTONOMOUS_TRANSACTION", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$CREATE PROCEDURE p IS PRAGMA AUTONOMOUS_TRANSACTION; BEGIN INSERT INTO t VALUES (1); COMMIT; END;$$",
     "procedure created"),
    ("X8", "Package spec + body with package-level state", "not in corpus (package-heavy sources)",
     "CREATE PACKAGE pk AS FUNCTION nxt RETURN NUMBER; END;$$"
     "CREATE PACKAGE BODY pk AS cnt NUMBER := 0; FUNCTION nxt RETURN NUMBER IS BEGIN cnt := cnt + 1; RETURN cnt; END; END;$$"
     "SELECT pk.nxt() FROM DUAL$$SELECT pk.nxt() FROM DUAL$$", "1 / 2"),
    ("X9", "User-defined exception + RAISE", "not in corpus",
     "DECLARE e_bad EXCEPTION; BEGIN RAISE e_bad; EXCEPTION WHEN e_bad THEN SELECT 'caught e_bad' FROM DUAL; END;$$",
     "caught e_bad"),
    ("X10", "PRAGMA EXCEPTION_INIT", "not in corpus",
     "DECLARE e_dup EXCEPTION; PRAGMA EXCEPTION_INIT(e_dup, -1); BEGIN NULL; END;$$", "block runs"),
    ("X11", "Explicit OPEN / FETCH / CLOSE with %NOTFOUND", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2)$$"
     "DECLARE CURSOR c IS SELECT a FROM t; v NUMBER; s NUMBER := 0; BEGIN OPEN c; LOOP FETCH c INTO v; EXIT WHEN c%NOTFOUND; s := s + v; END LOOP; CLOSE c; SELECT s FROM DUAL; END;$$",
     "3"),
    ("X12", "SYS_REFCURSOR OUT parameter", "not in corpus",
     "CREATE PROCEDURE p(rc OUT SYS_REFCURSOR) IS BEGIN OPEN rc FOR SELECT 1 FROM DUAL; END;$$", "procedure created"),
    ("X13", "ROWNUM", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2),(3)$$SELECT a FROM t WHERE ROWNUM <= 2$$", "2 rows"),
    ("X14", "(+) outer join operator", "not in corpus",
     "CREATE TABLE a (id NUMBER)$$CREATE TABLE b (id NUMBER)$$INSERT INTO a VALUES (1),(2)$$INSERT INTO b VALUES (1)$$"
     "SELECT a.id, b.id FROM a, b WHERE a.id = b.id(+) ORDER BY a.id$$", "1 1 / 2 NULL"),
    ("X15", "MINUS set operator", "not in corpus",
     "SELECT 1 FROM DUAL UNION SELECT 2 FROM DUAL MINUS SELECT 2 FROM DUAL$$", "1"),
    ("X16", "TO_CHAR(date, fmt)", "not in corpus",
     "SELECT TO_CHAR(DATE'2026-01-31','YYYY-MM-DD') FROM DUAL$$", "2026-01-31"),
    ("X16b", "TO_DATE(str, fmt)", "not in corpus",
     "SELECT TO_DATE('2026-02-01','YYYY-MM-DD') FROM DUAL$$", "2026-02-01"),
    ("X16c", "ADD_MONTHS (end-of-month rule)", "not in corpus",
     "SELECT ADD_MONTHS(DATE'2026-01-31', 1) FROM DUAL$$", "2026-02-28"),
    ("X16d", "MONTHS_BETWEEN", "not in corpus",
     "SELECT MONTHS_BETWEEN(DATE'2026-03-31', DATE'2026-01-31') FROM DUAL$$", "2"),
    ("X17", "NVL2", "not in corpus",
     "SELECT NVL2(NULL,'a','b') FROM DUAL$$", "b"),
    ("X17b", "SUBSTR with negative start", "not in corpus",
     "SELECT SUBSTR('abcdef', -2) FROM DUAL$$", "ef"),
    ("X17c", "INSTR with occurrence argument (4 args)", "not in corpus",
     "SELECT INSTR('a,b,c', ',', 1, 2) FROM DUAL$$", "4"),
    ("X18", "UTL_FILE", "not in corpus",
     "BEGIN UTL_FILE.FCLOSE_ALL; END;$$", "runs"),
    ("X19", "CREATE TYPE ... AS OBJECT", "not in corpus",
     "CREATE TYPE pt AS OBJECT (x NUMBER, y NUMBER)$$", "type created"),
    ("X20", "GOTO / labels", "not in corpus",
     "DECLARE n NUMBER := 0; BEGIN <<top>> n := n + 1; IF n < 3 THEN GOTO top; END IF; SELECT n FROM DUAL; END;$$", "3"),
    ("X21", "SELECT ... INTO raising TOO_MANY_ROWS", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$INSERT INTO t VALUES (1),(2)$$"
     "DECLARE v NUMBER; BEGIN SELECT a INTO v FROM t; EXCEPTION WHEN TOO_MANY_ROWS THEN SELECT 'caught' FROM DUAL; END;$$",
     "caught"),
    ("X22", "Statement-level trigger (no FOR EACH ROW)", "not in corpus",
     "CREATE TABLE t (a NUMBER)$$CREATE TRIGGER tr AFTER INSERT ON t BEGIN NULL; END;$$", "trigger created"),
    ("X23", "PIVOT", "not in corpus",
     "CREATE TABLE t (k VARCHAR2(5), v NUMBER)$$INSERT INTO t VALUES ('a',1),('b',2)$$"
     "SELECT * FROM t PIVOT (SUM(v) FOR k IN ('a' AS a, 'b' AS b))$$", "1 2"),
    # ---------------- added for the HR sample schema (corpus/oracle/hr) ----------------
    ("T13", "Named inline NOT NULL  col t CONSTRAINT c NOT NULL", "hr: all 7 tables",
     "CREATE TABLE t (a NUMBER CONSTRAINT t_a_nn NOT NULL)$$INSERT INTO t VALUES (NULL)$$",
     "table created; insert fails ORA-01400"),
    ("T14", "CREATE TABLE ... ORGANIZATION INDEX", "hr: countries",
     "CREATE TABLE t (a CHAR(2) NOT NULL, CONSTRAINT t_pk PRIMARY KEY (a)) ORGANIZATION INDEX$$",
     "table created"),
    ("T15", "CREATE UNIQUE INDEX x, then ADD CONSTRAINT x PRIMARY KEY uses it", "hr: 6 tables",
     "CREATE TABLE t (a NUMBER NOT NULL)$$CREATE UNIQUE INDEX t_pk ON t (a)$$"
     "ALTER TABLE t ADD ( CONSTRAINT t_pk PRIMARY KEY (a) )$$"
     "SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t'$$",
     "1 (the PK reuses the index)"),
    ("T16", "REFERENCES t without a column list (= its PK)", "hr: employees, job_history",
     "CREATE TABLE p (id NUMBER PRIMARY KEY)$$CREATE TABLE c (pid NUMBER, CONSTRAINT c_fk FOREIGN KEY (pid) REFERENCES p)$$",
     "table created"),
    ("T17", "ALTER TABLE ADD ( PK, self-referencing FK ) in one statement", "hr: employees",
     "CREATE TABLE t (id NUMBER NOT NULL, mgr NUMBER)$$"
     "ALTER TABLE t ADD ( CONSTRAINT t_pk PRIMARY KEY (id), CONSTRAINT t_fk FOREIGN KEY (mgr) REFERENCES t (id) )$$",
     "table altered"),
    ("T18", "ALTER TABLE ... DISABLE / ENABLE CONSTRAINT", "hr_populate: dept_mgr_fk",
     "CREATE TABLE p (id NUMBER PRIMARY KEY)$$CREATE TABLE c (pid NUMBER, CONSTRAINT c_fk FOREIGN KEY (pid) REFERENCES p (id))$$"
     "ALTER TABLE c DISABLE CONSTRAINT c_fk$$",
     "table altered"),
    ("T18b", "Re-enabling FK checks validates rows loaded meanwhile", "hr_populate: dept_mgr_fk",
     "CREATE TABLE p (id NUMBER PRIMARY KEY)$$CREATE TABLE c (pid NUMBER, CONSTRAINT c_fk FOREIGN KEY (pid) REFERENCES p (id))$$"
     "SET FOREIGN_KEY_CHECKS = 0$$INSERT INTO c VALUES (99)$$SET FOREIGN_KEY_CHECKS = 1$$SELECT COUNT(*) FROM c$$"
     "ALTER TABLE c DROP FOREIGN KEY c_fk$$ALTER TABLE c ADD ( CONSTRAINT c_fk FOREIGN KEY (pid) REFERENCES p (id) )$$",
     "ENABLE fails ORA-02298 on the orphan"),
    ("T19", "CREATE SEQUENCE ... MAXVALUE NOCACHE NOCYCLE, then past MAXVALUE", "hr: locations_seq",
     "CREATE SEQUENCE s START WITH 9800 INCREMENT BY 100 MAXVALUE 9900 NOCACHE NOCYCLE$$"
     "SELECT s.NEXTVAL FROM DUAL$$SELECT s.NEXTVAL FROM DUAL$$SELECT s.NEXTVAL FROM DUAL$$",
     "9800 / 9900 / ORA-08004"),
    ("T20", "COMMENT ON TABLE / COLUMN", "hr: all tables",
     "CREATE TABLE t (a NUMBER)$$COMMENT ON TABLE t IS 'x'$$COMMENT ON COLUMN t.a IS 'y'$$",
     "comment created"),
    ("T21", "NUMBER(2,2): 0.994 rounds, 1 is out of range", "hr: employees.commission_pct",
     "CREATE TABLE t (a NUMBER(2,2))$$INSERT INTO t VALUES (0.994)$$INSERT INTO t VALUES (1)$$SELECT a FROM t$$",
     "0.99; second insert fails ORA-01438"),
    ("F14", "TO_DATE(str, 'dd-MM-yyyy')", "hr_populate: 127 rows",
     "SELECT TO_DATE('17-06-2013', 'dd-MM-yyyy') FROM DUAL$$", "2013-06-17"),
    ("F14b", "CREATE FUNCTION to_date (user shim)", "hr: shim not possible on 13.0",
     "CREATE FUNCTION to_date(s VARCHAR2, f VARCHAR2) RETURN DATE IS BEGIN RETURN NULL; END;$$",
     "function created"),
    ("F15", "TO_CHAR(d, 'DY') IN ('SAT','SUN') under a binary collation", "hr: secure_dml",
     "SELECT TO_CHAR(DATE '2026-11-07', 'DY'), "
     "CASE WHEN TO_CHAR(DATE '2026-11-07', 'DY') COLLATE utf8mb4_nopad_bin IN ('SAT', 'SUN') THEN 1 ELSE 0 END FROM DUAL$$",
     "SAT 1"),
    ("D4", "CREATE VIEW ... WITH READ ONLY", "hr: emp_details_view",
     "CREATE TABLE t (a NUMBER)$$CREATE VIEW v AS SELECT a FROM t WITH READ ONLY$$", "view created"),
    ("D4b", "Join view updatable without READ ONLY; ALGORITHM=TEMPTABLE is not", "hr: emp_details_view",
     "CREATE TABLE a (id NUMBER PRIMARY KEY, s NUMBER)$$CREATE TABLE b (id NUMBER PRIMARY KEY)$$"
     "INSERT INTO a VALUES (1, 5)$$INSERT INTO b VALUES (1)$$"
     "CREATE VIEW v1 AS SELECT a.id, a.s FROM a, b WHERE a.id = b.id$$"
     "CREATE ALGORITHM=TEMPTABLE VIEW v2 AS SELECT a.id, a.s FROM a, b WHERE a.id = b.id$$"
     "UPDATE v1 SET s = 6$$SELECT s FROM a$$UPDATE v2 SET s = 7$$",
     "(READ ONLY view) ORA-42399 on UPDATE"),
    ("D5", "ALTER SESSION SET NLS_LANGUAGE", "hr_populate, hr_install",
     "ALTER SESSION SET NLS_LANGUAGE=American$$", "session altered"),
    ("R8", "ALTER TRIGGER ... DISABLE", "hr: secure_employees",
     "CREATE TABLE t (a NUMBER)$$CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW BEGIN NULL; END;$$"
     "ALTER TRIGGER tr DISABLE$$", "trigger altered"),
]


def run_probe(script, mode):
    container = os.environ.get("MDB_CONTAINER", "lms-mariadb")
    db = "probe"
    base = ["docker", "exec", "-i", container, "mariadb",
            "-u" + os.environ.get("MDB_USER", "root"), "-p" + os.environ.get("MDB_PASSWORD", "root")]
    subprocess.run(base + ["-e", f"DROP DATABASE IF EXISTS {db}; CREATE DATABASE {db}"], capture_output=True)
    body = f"SET sql_mode='{mode}';\nDELIMITER $$\n" + script.replace("$$", "\n$$\n")
    p = subprocess.run(base + [db, "--batch", "--skip-column-names", "--force"],
                       input=body, capture_output=True, text=True)
    err = " | ".join(l for l in p.stderr.splitlines() if "Using a password" not in l)
    out = " / ".join(l.replace("\t", " ") for l in p.stdout.splitlines())
    return out, err


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extra-mode", action="append", default=[])
    ap.add_argument("--json")
    ap.add_argument("--md")
    a = ap.parse_args()
    mode = ",".join(["ORACLE"] + a.extra_mode)
    rows = []
    for pid, feature, used_in, script, oracle in PROBES:
        out, err = run_probe(script, mode)
        rows.append(dict(id=pid, feature=feature, used_in=used_in, oracle=oracle,
                         mariadb_output=out, mariadb_error=err))
        print(f"{pid:4} {feature[:55]:55} | out: {out[:70]}{' | ERR: ' + err[:150] if err else ''}")
    if a.json:
        json.dump({"sql_mode": mode, "probes": rows}, open(a.json, "w"), indent=2)
    if a.md:
        with open(a.md, "w") as f:
            f.write(f"# Feature probe results (sql_mode={mode})\n\nGenerated by `migration/tools/probe_features.py`.\n\n")
            f.write("| ID | Feature | Used in | Oracle (documented) | MariaDB output | MariaDB error |\n|---|---|---|---|---|---|\n")
            for r in rows:
                cells = [r["id"], r["feature"], r["used_in"], r["oracle"], r["mariadb_output"], r["mariadb_error"]]
                f.write("| " + " | ".join(c.replace("|", "\\|") for c in cells) + " |\n")


if __name__ == "__main__":
    main()
