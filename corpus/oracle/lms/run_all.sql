-- Run from SQL*Plus / SQLcl in this folder:   @run_all.sql
-- In SQL Developer: open this file and press F5 (Run Script).
SET ECHO ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

@@01_drop.sql
@@02_schema.sql
@@03_plsql.sql
@@04_data.sql
@@05_views.sql
@@06_queries.sql
