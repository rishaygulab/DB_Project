-- =============================================================
-- Library Management System - MariaDB 11.8 (sql_mode=ORACLE)
-- 00_compat.sql : small Oracle compatibility layer (NEW FILE, no Oracle counterpart)
--
-- Each shim stands in for an Oracle built-in that MariaDB 11.8 does not have,
-- so the application objects can call it with their original source text.
-- Remove a shim once the pinned MariaDB version provides the built-in
-- (MariaDB 13.0 already has TRUNC(date); see migration/COMPATIBILITY_MATRIX.md).
-- =============================================================

-- ---------- RAISE_APPLICATION_ERROR(-200xx, msg) ----------
-- Oracle: raises ORA-200xx with the message; SQLCODE = -200xx.
-- Here:   raises SQLSTATE 45000 with error number 200xx (positive, MariaDB
--         error numbers cannot be negative, so SQLCODE = +200xx). The message
--         carries the "ORA-200xx: " prefix so SQLERRM and client-side text match
--         Oracle for callers that print or parse it.
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

-- ---------- TRUNC(date) ----------
-- Oracle TRUNC(d) drops the time part. Only the DATE overload is provided;
-- TRUNC(number) is not used by this corpus.
-- NOTE: TRUNC(a) - TRUNC(b) is still wrong here (see DATEDIFF rewrites).
CREATE OR REPLACE FUNCTION trunc (
  p_date IN DATE
) RETURN DATE
DETERMINISTIC
IS
BEGIN
  RETURN CAST(p_date AS DATE);
END;
/

-- ---------- DBMS_OUTPUT.PUT_LINE ----------
-- Oracle buffers lines and the client prints them after the call.
-- Here each line comes back immediately as a one-column result set.
CREATE OR REPLACE PACKAGE dbms_output AS
  PROCEDURE put_line(p_line IN VARCHAR2);
END;
/

CREATE OR REPLACE PACKAGE BODY dbms_output AS
  PROCEDURE put_line(p_line IN VARCHAR2) IS
  BEGIN
    SELECT p_line AS dbms_output FROM DUAL;
  END;
END;
/
