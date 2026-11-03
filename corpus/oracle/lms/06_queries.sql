-- =============================================================
-- Library Management System - Oracle
-- 06_queries.sql : demonstration queries (SQL concepts)
-- =============================================================
SET LINESIZE 200
SET PAGESIZE 100
SET SERVEROUTPUT ON

-- Q1. Simple SELECT with WHERE + ORDER BY: CS books, newest first
SELECT title, pub_year, available_copies
  FROM books
 WHERE category_id = (SELECT category_id FROM categories WHERE name = 'Computer Science')
 ORDER BY pub_year DESC;

-- Q2. INNER JOIN (3 tables): who wrote which book
SELECT b.title, a.name AS author
  FROM books b
  JOIN book_authors ba ON ba.book_id  = b.book_id
  JOIN authors a       ON a.author_id = ba.author_id
 ORDER BY b.title, a.name;

-- Q3. LEFT OUTER JOIN: books never borrowed
SELECT b.title
  FROM books b
  LEFT JOIN loans l ON l.book_id = b.book_id
 WHERE l.loan_id IS NULL;

-- Q4. GROUP BY + HAVING: categories with more than one title
SELECT c.name AS category, COUNT(*) AS titles, SUM(b.total_copies) AS copies
  FROM books b
  JOIN categories c ON c.category_id = b.category_id
 GROUP BY c.name
HAVING COUNT(*) > 1;

-- Q5. Aggregates: most borrowed books
SELECT b.title, COUNT(l.loan_id) AS times_borrowed
  FROM books b
  JOIN loans l ON l.book_id = b.book_id
 GROUP BY b.title
 ORDER BY times_borrowed DESC
 FETCH FIRST 3 ROWS ONLY;

-- Q6. Subquery (IN): members who have borrowed a Computer Science book
SELECT first_name, last_name
  FROM members
 WHERE member_id IN (SELECT l.member_id
                       FROM loans l
                       JOIN books b ON b.book_id = l.book_id
                       JOIN categories c ON c.category_id = b.category_id
                      WHERE c.name = 'Computer Science');

-- Q7. Correlated subquery (EXISTS): members with an overdue book right now
SELECT m.first_name, m.last_name, m.email
  FROM members m
 WHERE EXISTS (SELECT 1 FROM loans l
                WHERE l.member_id = m.member_id
                  AND l.return_date IS NULL
                  AND l.due_date < TRUNC(SYSDATE));

-- Q8. NOT EXISTS: members who have never borrowed anything
SELECT first_name, last_name
  FROM members m
 WHERE NOT EXISTS (SELECT 1 FROM loans l WHERE l.member_id = m.member_id);

-- Q9. Analytic / window function: rank books by popularity within category
SELECT category, title, borrows,
       RANK() OVER (PARTITION BY category ORDER BY borrows DESC) AS rank_in_category
  FROM (SELECT c.name AS category, b.title, COUNT(l.loan_id) AS borrows
          FROM books b
          JOIN categories c ON c.category_id = b.category_id
          LEFT JOIN loans l ON l.book_id = b.book_id
         GROUP BY c.name, b.title);

-- Q10. Set operation (UNION): everyone with an email in the system
SELECT first_name || ' ' || last_name AS name, email, 'MEMBER' AS kind FROM members
UNION
SELECT name, email, 'STAFF' FROM staff
ORDER BY kind, name;

-- Q11. CASE + date functions: loan status report
SELECT loan_id, book_id, member_id, due_date, return_date,
       CASE
         WHEN return_date IS NULL AND due_date < TRUNC(SYSDATE) THEN 'OVERDUE'
         WHEN return_date IS NULL                              THEN 'ON LOAN'
         WHEN return_date > due_date                           THEN 'RETURNED LATE'
         ELSE 'RETURNED'
       END AS loan_status
  FROM loans
 ORDER BY loan_id;

-- Q12. Fine collection summary
SELECT paid, COUNT(*) AS fines, SUM(amount) AS total
  FROM fines
 GROUP BY paid;

-- Q13. Views
SELECT * FROM v_book_catalog ORDER BY title;
SELECT * FROM v_active_loans ORDER BY due_date;
SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC;
SELECT * FROM v_member_summary ORDER BY member_id;

-- Q14. Audit trail written by trigger
SELECT * FROM book_audit ORDER BY audit_id;

-- -------------------------------------------------------------
-- PL/SQL demos: stored procedures and error handling
-- -------------------------------------------------------------

-- D1. Issue a book successfully (Priya borrows '1984')
DECLARE
  v_loan_id NUMBER;
BEGIN
  issue_book(p_book_id => 4, p_member_id => 2, p_staff_id => 1, p_loan_id => v_loan_id);
  DBMS_OUTPUT.PUT_LINE('Issued, loan id = ' || v_loan_id);
END;
/

-- D2. Rejected: suspended member
BEGIN
  DECLARE v_loan_id NUMBER;
  BEGIN
    issue_book(4, 6, 1, v_loan_id);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

-- D3. Rejected: no copies left ('Learning SQL' has 1 copy, already on loan)
BEGIN
  DECLARE v_loan_id NUMBER;
  BEGIN
    issue_book(8, 1, 1, v_loan_id);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

-- D4. Return an overdue book -> trigger creates a fine
BEGIN
  return_book(3);
  DBMS_OUTPUT.PUT_LINE('Priya now owes: ' || fn_member_dues(2));
END;
/

-- D5. Rejected: Priya has unpaid fines now
BEGIN
  DECLARE v_loan_id NUMBER;
  BEGIN
    issue_book(5, 2, 1, v_loan_id);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

-- D6. Pay the fine
DECLARE
  v_fine_id fines.fine_id%TYPE;
BEGIN
  SELECT fine_id INTO v_fine_id FROM fines WHERE loan_id = 3;
  pay_fine(v_fine_id);
  DBMS_OUTPUT.PUT_LINE('Paid. Priya now owes: ' || fn_member_dues(2));
END;
/

-- D7. Cursor loop: print overdue reminder letters
DECLARE
  CURSOR c_overdue IS
    SELECT member_name, email, title, days_overdue, fine_so_far
      FROM v_overdue_loans;
BEGIN
  FOR r IN c_overdue LOOP
    DBMS_OUTPUT.PUT_LINE('To: ' || r.email || ' | Dear ' || r.member_name ||
                         ', "' || r.title || '" is ' || r.days_overdue ||
                         ' day(s) overdue. Fine so far: ' || r.fine_so_far);
  END LOOP;
END;
/
