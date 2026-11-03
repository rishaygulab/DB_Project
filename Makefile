# One command per task. Each team member adds targets in their own section.
PY      := .venv/bin/python
MDB_VER := 11.8
LATEST  := 13.0

.PHONY: setup mariadb load baseline probe verify verify-naive verify-latest diff check

setup:
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements.txt

# ---------- Person 1: environment (placeholder until the Oracle container lands) ----------
mariadb:
	docker start lms-mariadb 2>/dev/null || docker run -d --name lms-mariadb -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3307:3306 mariadb:$(MDB_VER)
	docker start lms-mariadb-13 2>/dev/null || docker run -d --name lms-mariadb-13 -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=lms -p 3308:3306 mariadb:$(LATEST)
	@until docker exec lms-mariadb mariadb -uroot -proot -e "select 1" >/dev/null 2>&1; do sleep 2; done; echo "MariaDB $(MDB_VER) ready on 3307"
	@until docker exec lms-mariadb-13 mariadb -uroot -proot -e "select 1" >/dev/null 2>&1; do sleep 2; done; echo "MariaDB $(LATEST) ready on 3308"

# ---------- Person 2: migration and compatibility matrix ----------
load:                     ## migrated corpus into MariaDB 11.8, recommended settings
	$(PY) migration/tools/run_objects.py --reset --quiet corpus/mariadb/lms/0*.sql

baseline:                 ## UNCHANGED Oracle files under plain sql_mode=ORACLE (expected to fail)
	-$(PY) migration/tools/run_objects.py --reset --sql-mode ORACLE --autocommit 1 --collation default --quiet \
	  --json migration/probes/baseline_unchanged.json $(filter-out corpus/oracle/lms/01_drop.sql,$(wildcard corpus/oracle/lms/0*.sql))

probe:                    ## one probe per Oracle feature, on 11.8 (two modes) and latest
	python3 migration/tools/probe_features.py --json migration/probes/features_oracle_mode.json --md migration/probes/features_oracle_mode.md
	python3 migration/tools/probe_features.py --extra-mode EMPTY_STRING_IS_NULL --json migration/probes/features_oracle_esin.json --md migration/probes/features_oracle_esin.md
	MDB_CONTAINER=lms-mariadb-13 python3 migration/tools/probe_features.py --json migration/probes/features_oracle_mode_$(LATEST).json --md migration/probes/features_oracle_mode_$(LATEST).md

verify:                   ## object-level cases, recommended settings (expect all pass)
	$(PY) migration/tools/verify_objects.py --json migration/verify/results_recommended_$(MDB_VER).json

verify-naive:             ## same cases with only sql_mode=ORACLE (shows the silent differences)
	-$(PY) migration/tools/verify_objects.py --sql-mode ORACLE --collation default --autocommit 1 --json migration/verify/results_naive_$(MDB_VER).json

verify-latest:
	MDB_PORT=3308 $(PY) migration/tools/verify_objects.py --json migration/verify/results_recommended_$(LATEST).json

diff:                     ## regenerate the migration diff
	-diff -ru corpus/oracle/lms corpus/mariadb/lms > migration/corpus.diff

check: load verify verify-latest diff   ## run before every commit to the migration part

# ---------- Person 3: harness and guide ----------
