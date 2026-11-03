-- =============================================================
-- Library Management System - MariaDB 11.8 (sql_mode=ORACLE)
-- 01_drop.sql : remove existing objects so the scripts can be re-run
--
-- MIGRATION: REDESIGNED. The Oracle version loops over USER_TABLES /
-- USER_SEQUENCES / USER_OBJECTS (no such views in MariaDB) and uses
-- DROP TABLE ... CASCADE CONSTRAINTS PURGE (no such syntax). MariaDB has
-- IF EXISTS on every DROP, so the dictionary loop is not needed at all.
-- FOREIGN_KEY_CHECKS=0 plays the role of CASCADE CONSTRAINTS.
-- =============================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS book_audit, fines, loans, book_authors, books,
                     categories, publishers, authors, staff, members;

DROP SEQUENCE IF EXISTS seq_member, seq_author, seq_publisher, seq_category,
                        seq_book, seq_staff, seq_loan, seq_fine, seq_audit;

DROP VIEW IF EXISTS v_book_catalog, v_active_loans, v_overdue_loans, v_member_summary;

DROP PROCEDURE IF EXISTS issue_book;
DROP PROCEDURE IF EXISTS return_book;
DROP PROCEDURE IF EXISTS pay_fine;
DROP FUNCTION IF EXISTS fn_calc_fine;
DROP FUNCTION IF EXISTS fn_member_dues;
DROP FUNCTION IF EXISTS fn_loan_days;

SET FOREIGN_KEY_CHECKS = 1;
