-- =============================================================
-- Library Management System - Oracle
-- 04_data.sql : sample data
-- Run after 03_plsql.sql so triggers keep stock and fines correct.
-- =============================================================

-- ---------- Categories ----------
INSERT INTO categories (name) VALUES ('Computer Science');   -- 1
INSERT INTO categories (name) VALUES ('Mathematics');        -- 2
INSERT INTO categories (name) VALUES ('Fiction');            -- 3
INSERT INTO categories (name) VALUES ('History');            -- 4
INSERT INTO categories (name) VALUES ('Science');            -- 5

-- ---------- Publishers ----------
INSERT INTO publishers (name, city) VALUES ('Pearson', 'London');          -- 1
INSERT INTO publishers (name, city) VALUES ('McGraw-Hill', 'New York');    -- 2
INSERT INTO publishers (name, city) VALUES ('Penguin', 'London');          -- 3
INSERT INTO publishers (name, city) VALUES ('O''Reilly', 'Sebastopol');    -- 4
INSERT INTO publishers (name, city) VALUES ('Oxford University Press', 'Oxford'); -- 5

-- ---------- Authors ----------
INSERT INTO authors (name, country) VALUES ('Abraham Silberschatz', 'USA');     -- 1
INSERT INTO authors (name, country) VALUES ('Henry F. Korth', 'USA');           -- 2
INSERT INTO authors (name, country) VALUES ('S. Sudarshan', 'India');           -- 3
INSERT INTO authors (name, country) VALUES ('Ramez Elmasri', 'USA');            -- 4
INSERT INTO authors (name, country) VALUES ('Shamkant Navathe', 'USA');         -- 5
INSERT INTO authors (name, country) VALUES ('Thomas H. Cormen', 'USA');         -- 6
INSERT INTO authors (name, country) VALUES ('George Orwell', 'UK');             -- 7
INSERT INTO authors (name, country) VALUES ('Yuval Noah Harari', 'Israel');     -- 8
INSERT INTO authors (name, country) VALUES ('Stephen Hawking', 'UK');           -- 9
INSERT INTO authors (name, country) VALUES ('Gilbert Strang', 'USA');           -- 10

-- ---------- Books (available_copies starts = total_copies) ----------
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0078022159', 'Database System Concepts', 2, 1, 2019, 5, 5);            -- 1
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0133970777', 'Fundamentals of Database Systems', 1, 1, 2015, 4, 4);    -- 2
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0262033848', 'Introduction to Algorithms', 2, 1, 2009, 3, 3);          -- 3
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0451524935', '1984', 3, 3, 1949, 6, 6);                                -- 4
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0062316097', 'Sapiens', 3, 4, 2015, 3, 3);                             -- 5
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0553380163', 'A Brief History of Time', 3, 5, 1998, 2, 2);             -- 6
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-0980232776', 'Introduction to Linear Algebra', 5, 2, 2016, 2, 2);      -- 7
INSERT INTO books (isbn, title, publisher_id, category_id, pub_year, total_copies, available_copies)
VALUES ('978-1492043454', 'Learning SQL', 4, 1, 2020, 1, 1);                        -- 8

-- ---------- Book ↔ Author ----------
INSERT INTO book_authors VALUES (1, 1);
INSERT INTO book_authors VALUES (1, 2);
INSERT INTO book_authors VALUES (1, 3);
INSERT INTO book_authors VALUES (2, 4);
INSERT INTO book_authors VALUES (2, 5);
INSERT INTO book_authors VALUES (3, 6);
INSERT INTO book_authors VALUES (4, 7);
INSERT INTO book_authors VALUES (5, 8);
INSERT INTO book_authors VALUES (6, 9);
INSERT INTO book_authors VALUES (7, 10);

-- ---------- Members ----------
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date)
VALUES ('Aarav', 'Sharma', 'aarav.sharma@example.com', '9800000001', 'STUDENT', DATE '2025-08-01');  -- 1
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date)
VALUES ('Priya', 'Thapa', 'priya.thapa@example.com', '9800000002', 'STUDENT', DATE '2025-08-15');    -- 2
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date)
VALUES ('Ravi', 'Kumar', 'ravi.kumar@example.com', '9800000003', 'FACULTY', DATE '2024-01-10');      -- 3
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date)
VALUES ('Emma', 'Lee', 'emma.lee@example.com', '9800000004', 'PUBLIC', DATE '2026-02-20');           -- 4
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date)
VALUES ('Sita', 'Gurung', 'sita.gurung@example.com', '9800000005', 'STUDENT', DATE '2026-01-05');    -- 5
INSERT INTO members (first_name, last_name, email, phone, member_type, join_date, status)
VALUES ('John', 'Doe', 'john.doe@example.com', '9800000006', 'PUBLIC', DATE '2025-05-05', 'SUSPENDED'); -- 6

-- ---------- Staff ----------
INSERT INTO staff (name, role, email) VALUES ('Maya Rai', 'LIBRARIAN', 'maya.rai@library.org');   -- 1
INSERT INTO staff (name, role, email) VALUES ('Bikash KC', 'ASSISTANT', 'bikash.kc@library.org'); -- 2
INSERT INTO staff (name, role, email) VALUES ('Admin User', 'ADMIN', 'admin@library.org');        -- 3

-- ---------- Loans (inserted open; trigger decrements stock) ----------
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (1, 1, 1, DATE '2026-09-01', DATE '2026-09-15');   -- 1 returned late
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (4, 1, 2, DATE '2026-10-20', DATE '2026-11-03');   -- 2 open
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (3, 2, 1, DATE '2026-09-20', DATE '2026-10-04');   -- 3 open, overdue
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (1, 3, 1, DATE '2026-10-01', DATE '2026-10-31');   -- 4 open
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (5, 4, 2, DATE '2026-08-01', DATE '2026-08-08');   -- 5 returned on time
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (6, 5, 2, DATE '2026-09-10', DATE '2026-09-24');   -- 6 returned late
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (8, 3, 1, DATE '2026-10-10', DATE '2026-11-09');   -- 7 open (last copy)
INSERT INTO loans (book_id, member_id, staff_id, loan_date, due_date)
VALUES (2, 5, 1, DATE '2026-10-05', DATE '2026-10-19');   -- 8 open, overdue

-- ---------- Returns (trigger restocks and creates fines) ----------
UPDATE loans SET return_date = DATE '2026-09-20' WHERE loan_id = 1;  -- 5 days late -> 25.00
UPDATE loans SET return_date = DATE '2026-08-07' WHERE loan_id = 5;  -- on time
UPDATE loans SET return_date = DATE '2026-09-26' WHERE loan_id = 6;  -- 2 days late -> 10.00

-- Aarav paid his fine
UPDATE fines SET paid = 'Y', paid_date = DATE '2026-09-21'
 WHERE loan_id = 1;

COMMIT;
