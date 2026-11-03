-- =============================================================
-- Library Management System - Oracle
-- 01_drop.sql : remove existing objects so the scripts can be re-run
-- =============================================================

BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('BOOK_AUDIT','FINES','LOANS','BOOK_AUTHORS','BOOKS',
                                 'CATEGORIES','PUBLISHERS','AUTHORS','STAFF','MEMBERS'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;

  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_MEMBER','SEQ_AUTHOR','SEQ_PUBLISHER','SEQ_CATEGORY',
                                    'SEQ_BOOK','SEQ_STAFF','SEQ_LOAN','SEQ_FINE','SEQ_AUDIT'))
  LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;

  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('PROCEDURE','FUNCTION','VIEW')
              AND object_name IN ('ISSUE_BOOK','RETURN_BOOK','PAY_FINE','FN_CALC_FINE',
                                  'FN_MEMBER_DUES','FN_LOAN_DAYS','V_BOOK_CATALOG',
                                  'V_ACTIVE_LOANS','V_OVERDUE_LOANS','V_MEMBER_SUMMARY'))
  LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
  END LOOP;
END;
/
