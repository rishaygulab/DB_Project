#!/usr/bin/env python3
"""Run SQL scripts against MariaDB one statement at a time, in ONE session, and
report each statement's result.

Statements are split the way SQL*Plus splits them: PL/SQL units (CREATE
FUNCTION/PROCEDURE/TRIGGER/PACKAGE, anonymous BEGIN/DECLARE blocks) end at a
line holding only '/', everything else ends at ';'. SQL*Plus client commands
(SET LINESIZE, @@, WHENEVER, ...) are skipped because they never reach the
server. This lets corpus/oracle/lms and corpus/mariadb/lms keep the same file layout,
so `diff -r corpus/oracle/lms corpus/mariadb/lms` shows only migration changes.

Usage:
  run_objects.py [--sql-mode MODE] [--autocommit 0|1] [--reset [--collation C]]
                 [--json out.json] [--quiet] file.sql [file.sql ...]

Connection from env: MDB_HOST (127.0.0.1), MDB_PORT (3307), MDB_USER (root),
MDB_PASSWORD (root), MDB_DATABASE (lms).
"""
import argparse
import json
import os
import re
import sys

import pymysql

RECOMMENDED_MODE = "ORACLE,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,EMPTY_STRING_IS_NULL"
# Oracle compares VARCHAR2 binary and without blank padding; this collation does the same.
RECOMMENDED_COLLATION = "utf8mb4_nopad_bin"

PLSQL_START = re.compile(
    r"^\s*(CREATE\s+(OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE|TRIGGER|PACKAGE)\b|BEGIN\b|DECLARE\b)",
    re.I,
)
SQLPLUS_CMD = re.compile(
    r"^\s*(SET\s+(ECHO|SERVEROUTPUT|LINESIZE|PAGESIZE|FEEDBACK|DEFINE)\b|@|WHENEVER\b|PROMPT\b|SPOOL\b)",
    re.I,
)
NAME = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:UNIQUE\s+)?(TABLE|VIEW|SEQUENCE|INDEX|FUNCTION|PROCEDURE|TRIGGER|PACKAGE(?:\s+BODY)?)\s+(\w+)",
    re.I,
)


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines() if not l.strip().startswith("--")).strip()


def split_statements(sql):
    stmts, buf, in_plsql = [], [], False
    for line in sql.splitlines():
        if not buf:
            if not line.strip() or line.strip().startswith("--"):
                continue
            if SQLPLUS_CMD.match(line):
                continue
            in_plsql = bool(PLSQL_START.match(line))
        if in_plsql:
            if line.strip() == "/":
                stmts.append("\n".join(buf).strip())
                buf, in_plsql = [], False
            else:
                buf.append(line)
            continue
        buf.append(line)
        # a ';' outside a trailing comment ends a plain SQL statement
        code = re.sub(r"--.*$", "", line)
        if code.rstrip().endswith(";"):
            stmts.append("\n".join(buf).strip().rstrip(";"))
            buf = []
    if buf and strip_comment_lines("\n".join(buf)):
        stmts.append("\n".join(buf).strip())
    return [s for s in stmts if strip_comment_lines(s)]


def label(stmt):
    body = strip_comment_lines(stmt)
    m = NAME.search(body)
    if m:
        return f"{m.group(1).upper()} {m.group(2).lower()}"
    return " ".join(body.split())[:70]


def connect(sql_mode, autocommit, database=None):
    conn = pymysql.connect(
        host=os.environ.get("MDB_HOST", "127.0.0.1"),
        port=int(os.environ.get("MDB_PORT", "3307")),
        user=os.environ.get("MDB_USER", "root"),
        password=os.environ.get("MDB_PASSWORD", "root"),
        database=database,
        autocommit=bool(autocommit),
        client_flag=pymysql.constants.CLIENT.MULTI_RESULTS,
    )
    with conn.cursor() as c:
        c.execute(f"SET SESSION sql_mode = '{sql_mode}'")
    return conn


def execute(conn, stmt):
    """Run one statement; return (ok, rows-as-text, error, warnings)."""
    out, warnings = [], []
    with conn.cursor() as c:
        try:
            c.execute(stmt)
            while True:
                if c.description:
                    out.extend(" ".join("NULL" if v is None else str(v) for v in row) for row in c.fetchall())
                if not c.nextset():
                    break
        except pymysql.MySQLError as e:
            return False, out, f"{e.args[0]}: {e.args[1]}" if len(e.args) > 1 else str(e), warnings
        c.execute("SHOW WARNINGS")
        warnings = [f"{r[1]}: {r[2]}" for r in c.fetchall()]
    return True, out, "", warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql-mode", default=RECOMMENDED_MODE)
    ap.add_argument("--autocommit", type=int, default=0)
    ap.add_argument("--reset", action="store_true", help="drop and recreate the database first")
    ap.add_argument("--collation", default=RECOMMENDED_COLLATION,
                    help="database collation used by --reset ('default' = server default)")
    ap.add_argument("--json")
    ap.add_argument("--quiet", action="store_true", help="print only failures")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    db = os.environ.get("MDB_DATABASE", "lms")

    if a.reset:
        admin = connect(a.sql_mode, 1)
        with admin.cursor() as c:
            c.execute(f"DROP DATABASE IF EXISTS {db}")
            c.execute(f"CREATE DATABASE {db}" + ("" if a.collation == "default" else f" COLLATE {a.collation}"))
        admin.close()
    conn = connect(a.sql_mode, a.autocommit, db)

    results, failures = [], 0
    for f in a.files:
        for stmt in split_statements(open(f, encoding="utf-8").read()):
            ok, out, err, warns = execute(conn, stmt)
            failures += not ok
            results.append({"file": os.path.basename(f), "object": label(stmt), "ok": ok,
                            "error": err, "warnings": warns, "output": out})
            if ok and a.quiet:
                continue
            print(f"[{'OK  ' if ok else 'FAIL'}] {os.path.basename(f)}: {label(stmt)}")
            for line in ([f"ERROR {err}"] if err else []) + [f"WARN  {w}" for w in warns] + out:
                print("       " + line)
    conn.commit()
    if a.json:
        json.dump({"sql_mode": a.sql_mode, "autocommit": a.autocommit, "results": results},
                  open(a.json, "w"), indent=2)
    print(f"\n{len(results) - failures} ok, {failures} failed  (sql_mode={a.sql_mode}, autocommit={a.autocommit})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
