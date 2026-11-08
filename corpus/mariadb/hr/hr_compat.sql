-- =============================================================
-- HR sample schema - MariaDB 11.8 (sql_mode=ORACLE)
-- hr_compat.sql : Oracle compatibility layer (NEW FILE, no Oracle counterpart)
--
-- Load before hr_code.sql. Same shim as corpus/mariadb/lms/00_compat.sql; repeated
-- here because a shim lives in the database it is created in, and each corpus
-- loads into its own database.
--
-- No TO_DATE shim: 13.0 makes TO_DATE a keyword, so CREATE FUNCTION to_date fails
-- there. hr_populate.sql uses DATE literals instead (see its MIGRATION notes).
-- =============================================================

-- ---------- RAISE_APPLICATION_ERROR(-200xx, msg) ----------
-- Oracle: raises ORA-200xx with the message; SQLCODE = -200xx.
-- Here:   raises SQLSTATE 45000 with error number 200xx and the message
--         prefixed "ORA-200xx: ", as in corpus/mariadb/lms/00_compat.sql.
CREATE OR REPLACE PROCEDURE raise_application_error (
  p_code    IN INT,
  p_message IN VARCHAR2
)
IS
  v_errno INT := ABS(p_code);
  v_text  VARCHAR2(2048) := 'ORA-' || v_errno || ': ' || p_message;
BEGIN
  SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = v_errno, MESSAGE_TEXT = v_text;
END;
/
