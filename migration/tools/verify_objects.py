#!/usr/bin/env python3
"""Object-level verification of the migrated corpus.

For every case in a cases file: recreate the database, load the corpus files
it names (default: corpus/mariadb/lms 00..05) in one session, run the case's steps, and compare with
the Oracle-semantics expectation. Prints one line per case and a per-object
summary; --json writes the full results (consumed by the compatibility matrix).

Usage:
  verify_objects.py [--sql-mode MODE] [--collation C] [--autocommit 0|1]
                    [--cases migration/verify/cases.json] [--json out.json]
"""
import argparse
import datetime
import decimal
import json
import os
import re
import sys
from collections import OrderedDict

import pymysql

sys.path.insert(0, os.path.dirname(__file__))
from run_objects import RECOMMENDED_COLLATION, RECOMMENDED_MODE, connect, split_statements  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Defaults for a cases file without "corpus" / "load" keys (cases.json = LMS).
DEFAULT_CORPUS = "lms"
DEFAULT_LOAD = ["00_compat.sql", "01_drop.sql", "02_schema.sql", "03_plsql.sql", "04_data.sql", "05_views.sql"]


def norm(v):
    """Render a value the way the expectations are written: 25.00 / 25.0 -> '25', midnight datetime -> date."""
    if v is None:
        return "NULL"
    if isinstance(v, (float, decimal.Decimal)):
        d = decimal.Decimal(str(v)).normalize()
        return format(d, "f")
    if isinstance(v, datetime.datetime) and v.time() == datetime.time(0):
        return v.date().isoformat()
    if isinstance(v, (datetime.date, datetime.datetime)):
        return v.isoformat(sep=" ")
    return str(v)


def resolve(text, today):
    def sub(m):
        tok = m.group(1)
        if tok == "TODAY":
            return today.isoformat()
        if tok.startswith("TODAY+"):
            return (today + datetime.timedelta(days=int(tok[6:]))).isoformat()
        kind, _, d = tok.partition(":")
        days = (today - datetime.date.fromisoformat(d)).days
        return str(days if kind == "DAYS_SINCE" else days * 5)
    return re.sub(r"\{([A-Z_+0-9:-]+)\}", sub, text)


def load(sql_mode, collation, autocommit, db, corpus, files):
    admin = connect(sql_mode, 1)
    with admin.cursor() as c:
        c.execute(f"DROP DATABASE IF EXISTS {db}")
        c.execute(f"CREATE DATABASE {db}" + ("" if collation == "default" else f" COLLATE {collation}"))
    admin.close()
    conn = connect(sql_mode, autocommit, db)
    with conn.cursor() as c:
        for f in files:
            for stmt in split_statements(open(os.path.join(ROOT, "corpus", "mariadb", corpus, f)).read()):
                c.execute(stmt)
                while c.nextset():
                    pass
    conn.commit()
    return conn


def run_steps(conn, steps):
    rows, err = [], None
    with conn.cursor() as c:
        for s in steps:
            try:
                c.execute(s)
                rows = []
                while True:
                    if c.description:
                        rows = [[norm(v) for v in r] for r in c.fetchall()]
                    if not c.nextset():
                        break
            except pymysql.MySQLError as e:
                err = (e.args[0], e.args[1] if len(e.args) > 1 else "")
                break
    return rows, err


def check(case, rows, err, today):
    if "expect_error" in case:
        if not err:
            return False, f"expected error {case['expect_error']}, got rows {rows}"
        if err[0] != case["expect_error"]:
            return False, f"expected error {case['expect_error']}, got {err[0]}: {err[1]}"
        if "expect_message" in case and err[1] != case["expect_message"]:
            return False, f"message {err[1]!r} != {case['expect_message']!r}"
        return True, f"error {err[0]}: {err[1]}"
    if err:
        return False, f"unexpected error {err[0]}: {err[1]}"
    if "expect_contains" in case:
        ok = any(case["expect_contains"] in " ".join(r) for r in rows)
        return ok, "found" if ok else f"{case['expect_contains']!r} not in {rows}"
    expect = [[resolve(v, today) for v in r] for r in case["expect"]]
    return rows == expect, "" if rows == expect else f"got {rows}, expected {expect}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql-mode", default=RECOMMENDED_MODE)
    ap.add_argument("--collation", default=RECOMMENDED_COLLATION)
    ap.add_argument("--autocommit", type=int, default=0)
    ap.add_argument("--cases", default=os.path.join(ROOT, "migration", "verify", "cases.json"))
    ap.add_argument("--json")
    a = ap.parse_args()
    spec = json.load(open(a.cases))
    corpus, files = spec.get("corpus", DEFAULT_CORPUS), spec.get("load", DEFAULT_LOAD)
    db = os.environ.get("MDB_DATABASE", f"{corpus}_verify")
    cases = spec["cases"]

    results, per_obj = [], OrderedDict()
    for case in cases:
        conn = load(a.sql_mode, a.collation, a.autocommit, db, corpus, files)
        with conn.cursor() as c:
            c.execute("SELECT CURRENT_DATE")
            today = c.fetchone()[0]
        rows, err = run_steps(conn, case["steps"])
        conn.close()
        ok, detail = check(case, rows, err, today)
        results.append({"object": case["object"], "case": case["case"], "ok": ok, "detail": detail})
        per_obj.setdefault(case["object"], [0, 0])[0 if ok else 1] += 1
        print(f"[{'PASS' if ok else 'FAIL'}] {case['object']:20} {case['case']}" + ("" if ok else f"\n       {detail}"))

    print("\nPer object (pass/fail):")
    for o, (p, f) in per_obj.items():
        print(f"  {o:20} {p:2} pass  {f:2} fail")
    passed = sum(r["ok"] for r in results)
    print(f"\n{passed}/{len(results)} cases pass  (sql_mode={a.sql_mode}, collation={a.collation}, autocommit={a.autocommit})")
    if a.json:
        json.dump({"sql_mode": a.sql_mode, "collation": a.collation, "autocommit": a.autocommit,
                   "results": results}, open(a.json, "w"), indent=2)
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
