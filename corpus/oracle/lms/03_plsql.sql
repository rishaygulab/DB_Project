-- =============================================================
-- Library Management System - Oracle
-- 03_plsql.sql : functions, triggers, stored procedures
-- Business rules:
--   * Loan period: STUDENT 14 days, FACULTY 30 days, PUBLIC 7 days
--   * Max open loans: STUDENT 3, FACULTY 10, PUBLIC 2
--   * Late fine: 5.00 per day late
--   * Members with unpaid fines or SUSPENDED status cannot borrow
-- =============================================================

-- ---------- FUNCTION: fine for a given due/return date ----------
CREATE OR REPLACE FUNCTION fn_calc_fine (
  p_due_date    IN DATE,
  p_return_date IN DATE
) RETURN NUMBER
IS
  c_rate_per_day CONSTANT NUMBER := 5;
BEGIN
  IF p_return_date IS NULL OR TRUNC(p_return_date) <= TRUNC(p_due_date) THEN
    RETURN 0;
  END IF;
  RETURN (TRUNC(p_return_date) - TRUNC(p_due_date)) * c_rate_per_day;
END fn_calc_fine;
/

-- ---------- FUNCTION: loan period by member type ----------
CREATE OR REPLACE FUNCTION fn_loan_days (
  p_member_type IN VARCHAR2
) RETURN NUMBER
IS
BEGIN
  RETURN CASE p_member_type
           WHEN 'STUDENT' THEN 14
           WHEN 'FACULTY' THEN 30
           ELSE 7
         END;
END fn_loan_days;
/

-- ---------- FUNCTION: total unpaid fines of a member ----------
CREATE OR REPLACE FUNCTION fn_member_dues (
  p_member_id IN NUMBER
) RETURN NUMBER
IS
  v_total NUMBER;
BEGIN
  SELECT NVL(SUM(f.amount), 0)
    INTO v_total
    FROM fines f
    JOIN loans l ON l.loan_id = f.loan_id
   WHERE l.member_id = p_member_id
     AND f.paid = 'N';
  RETURN v_total;
END fn_member_dues;
/

-- ---------- TRIGGER: decrement stock when a book is lent ----------
CREATE OR REPLACE TRIGGER trg_loans_ai
AFTER INSERT ON loans
FOR EACH ROW
WHEN (NEW.return_date IS NULL)
BEGIN
  UPDATE books
     SET available_copies = available_copies - 1
   WHERE book_id = :NEW.book_id;
END;
/

-- ---------- TRIGGER: on return, restock and create fine if late ----------
CREATE OR REPLACE TRIGGER trg_loans_au_return
AFTER UPDATE OF return_date ON loans
FOR EACH ROW
WHEN (OLD.return_date IS NULL AND NEW.return_date IS NOT NULL)
DECLARE
  v_fine NUMBER;
BEGIN
  UPDATE books
     SET available_copies = available_copies + 1
   WHERE book_id = :NEW.book_id;

  v_fine := fn_calc_fine(:NEW.due_date, :NEW.return_date);
  IF v_fine > 0 THEN
    INSERT INTO fines (loan_id, amount) VALUES (:NEW.loan_id, v_fine);
  END IF;
END;
/

-- ---------- TRIGGER: audit inserts/updates/deletes on BOOKS ----------
CREATE OR REPLACE TRIGGER trg_books_audit
AFTER INSERT OR DELETE OR UPDATE OF title ON books
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO book_audit (book_id, action, new_title)
    VALUES (:NEW.book_id, 'INSERT', :NEW.title);
  ELSIF UPDATING THEN
    INSERT INTO book_audit (book_id, action, old_title, new_title)
    VALUES (:NEW.book_id, 'UPDATE', :OLD.title, :NEW.title);
  ELSE
    INSERT INTO book_audit (book_id, action, old_title)
    VALUES (:OLD.book_id, 'DELETE', :OLD.title);
  END IF;
END;
/

-- ---------- PROCEDURE: issue a book to a member ----------
CREATE OR REPLACE PROCEDURE issue_book (
  p_book_id   IN  NUMBER,
  p_member_id IN  NUMBER,
  p_staff_id  IN  NUMBER,
  p_loan_id   OUT NUMBER
)
IS
  v_available  books.available_copies%TYPE;
  v_type       members.member_type%TYPE;
  v_status     members.status%TYPE;
  v_open_loans NUMBER;
  v_limit      NUMBER;
BEGIN
  -- lock the book row so two staff can't lend the last copy at once
  SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id
     FOR UPDATE;

  SELECT member_type, status INTO v_type, v_status
    FROM members WHERE member_id = p_member_id;

  IF v_status <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Member is suspended.');
  END IF;

  IF v_available = 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'No copies available.');
  END IF;

  IF fn_member_dues(p_member_id) > 0 THEN
    RAISE_APPLICATION_ERROR(-20003, 'Member has unpaid fines.');
  END IF;

  SELECT COUNT(*) INTO v_open_loans
    FROM loans
   WHERE member_id = p_member_id AND return_date IS NULL;

  v_limit := CASE v_type WHEN 'STUDENT' THEN 3 WHEN 'FACULTY' THEN 10 ELSE 2 END;
  IF v_open_loans >= v_limit THEN
    RAISE_APPLICATION_ERROR(-20004, 'Loan limit of ' || v_limit || ' reached.');
  END IF;

  INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
  VALUES (p_book_id, p_member_id, p_staff_id,
          TRUNC(SYSDATE), TRUNC(SYSDATE) + fn_loan_days(v_type))
  RETURNING loan_id INTO p_loan_id;

  COMMIT;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20005, 'Book or member not found.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END issue_book;
/

-- ---------- PROCEDURE: return a book ----------
CREATE OR REPLACE PROCEDURE return_book (
  p_loan_id     IN NUMBER,
  p_return_date IN DATE DEFAULT TRUNC(SYSDATE)
)
IS
BEGIN
  UPDATE loans
     SET return_date = p_return_date
   WHERE loan_id = p_loan_id
     AND return_date IS NULL;

  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'Loan not found or already returned.');
  END IF;

  COMMIT;
END return_book;
/

-- ---------- PROCEDURE: pay a fine ----------
CREATE OR REPLACE PROCEDURE pay_fine (
  p_fine_id IN NUMBER
)
IS
BEGIN
  UPDATE fines
     SET paid = 'Y', paid_date = TRUNC(SYSDATE)
   WHERE fine_id = p_fine_id
     AND paid = 'N';

  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20007, 'Fine not found or already paid.');
  END IF;

  COMMIT;
END pay_fine;
/
