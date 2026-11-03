-- =============================================================
-- Library Management System - Oracle
-- 05_views.sql : reporting views
-- =============================================================

-- Full catalogue with authors listed in one column
CREATE OR REPLACE VIEW v_book_catalog AS
SELECT b.book_id,
       b.isbn,
       b.title,
       LISTAGG(a.name, ', ') WITHIN GROUP (ORDER BY a.name) AS authors,
       c.name  AS category,
       p.name  AS publisher,
       b.pub_year,
       b.total_copies,
       b.available_copies
  FROM books b
  JOIN categories c        ON c.category_id  = b.category_id
  JOIN publishers p        ON p.publisher_id = b.publisher_id
  LEFT JOIN book_authors ba ON ba.book_id    = b.book_id
  LEFT JOIN authors a      ON a.author_id    = ba.author_id
 GROUP BY b.book_id, b.isbn, b.title, c.name, p.name,
          b.pub_year, b.total_copies, b.available_copies;

-- Books currently on loan
CREATE OR REPLACE VIEW v_active_loans AS
SELECT l.loan_id,
       m.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       b.title,
       l.loan_date,
       l.due_date,
       s.name AS issued_by
  FROM loans l
  JOIN members m ON m.member_id = l.member_id
  JOIN books   b ON b.book_id   = l.book_id
  JOIN staff   s ON s.staff_id  = l.staff_id
 WHERE l.return_date IS NULL;

-- Open loans past their due date, with fine accrued so far
CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT l.loan_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       b.title,
       l.due_date,
       TRUNC(SYSDATE) - l.due_date        AS days_overdue,
       fn_calc_fine(l.due_date, SYSDATE)  AS fine_so_far
  FROM loans l
  JOIN members m ON m.member_id = l.member_id
  JOIN books   b ON b.book_id   = l.book_id
 WHERE l.return_date IS NULL
   AND l.due_date < TRUNC(SYSDATE);

-- One row per member: loan activity and dues
CREATE OR REPLACE VIEW v_member_summary AS
SELECT m.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       m.member_type,
       m.status,
       COUNT(l.loan_id)                                        AS total_loans,
       COUNT(CASE WHEN l.return_date IS NULL THEN 1 END)       AS open_loans,
       fn_member_dues(m.member_id)                             AS unpaid_fines
  FROM members m
  LEFT JOIN loans l ON l.member_id = m.member_id
 GROUP BY m.member_id, m.first_name, m.last_name, m.member_type, m.status;
