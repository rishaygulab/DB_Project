-- =============================================================
-- Library Management System - Oracle (12c or later)
-- 02_schema.sql : sequences, tables, constraints, indexes
-- All tables are in 3NF.
-- =============================================================

-- ---------- Sequences (surrogate primary keys) ----------
CREATE SEQUENCE seq_member    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_author    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_publisher START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_category  START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_book      START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_staff     START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_loan      START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_fine      START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_audit     START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---------- MEMBERS ----------
CREATE TABLE members (
  member_id    NUMBER        DEFAULT seq_member.NEXTVAL PRIMARY KEY,
  first_name   VARCHAR2(50)  NOT NULL,
  last_name    VARCHAR2(50)  NOT NULL,
  email        VARCHAR2(100) NOT NULL,
  phone        VARCHAR2(20),
  member_type  VARCHAR2(10)  NOT NULL,
  join_date    DATE          DEFAULT SYSDATE NOT NULL,
  status       VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
  CONSTRAINT uq_members_email  UNIQUE (email),
  CONSTRAINT ck_members_type   CHECK (member_type IN ('STUDENT','FACULTY','PUBLIC')),
  CONSTRAINT ck_members_status CHECK (status IN ('ACTIVE','SUSPENDED')),
  CONSTRAINT ck_members_email  CHECK (email LIKE '%_@_%._%')
);

-- ---------- AUTHORS ----------
CREATE TABLE authors (
  author_id  NUMBER        DEFAULT seq_author.NEXTVAL PRIMARY KEY,
  name       VARCHAR2(100) NOT NULL,
  country    VARCHAR2(50)
);

-- ---------- PUBLISHERS ----------
CREATE TABLE publishers (
  publisher_id NUMBER        DEFAULT seq_publisher.NEXTVAL PRIMARY KEY,
  name         VARCHAR2(100) NOT NULL,
  city         VARCHAR2(50),
  CONSTRAINT uq_publishers_name UNIQUE (name)
);

-- ---------- CATEGORIES ----------
CREATE TABLE categories (
  category_id NUMBER       DEFAULT seq_category.NEXTVAL PRIMARY KEY,
  name        VARCHAR2(50) NOT NULL,
  CONSTRAINT uq_categories_name UNIQUE (name)
);

-- ---------- BOOKS ----------
CREATE TABLE books (
  book_id          NUMBER        DEFAULT seq_book.NEXTVAL PRIMARY KEY,
  isbn             VARCHAR2(17)  NOT NULL,
  title            VARCHAR2(200) NOT NULL,
  publisher_id     NUMBER        NOT NULL,
  category_id      NUMBER        NOT NULL,
  pub_year         NUMBER(4),
  total_copies     NUMBER(3)     DEFAULT 1 NOT NULL,
  available_copies NUMBER(3)     DEFAULT 1 NOT NULL,
  CONSTRAINT uq_books_isbn      UNIQUE (isbn),
  CONSTRAINT fk_books_publisher FOREIGN KEY (publisher_id) REFERENCES publishers(publisher_id),
  CONSTRAINT fk_books_category  FOREIGN KEY (category_id)  REFERENCES categories(category_id),
  CONSTRAINT ck_books_copies    CHECK (total_copies >= 0 AND available_copies BETWEEN 0 AND total_copies),
  CONSTRAINT ck_books_year      CHECK (pub_year BETWEEN 1450 AND 2100)
);

-- ---------- BOOK_AUTHORS (M:N between BOOKS and AUTHORS) ----------
CREATE TABLE book_authors (
  book_id   NUMBER NOT NULL,
  author_id NUMBER NOT NULL,
  CONSTRAINT pk_book_authors PRIMARY KEY (book_id, author_id),
  CONSTRAINT fk_ba_book   FOREIGN KEY (book_id)   REFERENCES books(book_id)     ON DELETE CASCADE,
  CONSTRAINT fk_ba_author FOREIGN KEY (author_id) REFERENCES authors(author_id) ON DELETE CASCADE
);

-- ---------- STAFF ----------
CREATE TABLE staff (
  staff_id NUMBER        DEFAULT seq_staff.NEXTVAL PRIMARY KEY,
  name     VARCHAR2(100) NOT NULL,
  role     VARCHAR2(20)  NOT NULL,
  email    VARCHAR2(100) NOT NULL,
  CONSTRAINT uq_staff_email UNIQUE (email),
  CONSTRAINT ck_staff_role  CHECK (role IN ('LIBRARIAN','ASSISTANT','ADMIN'))
);

-- ---------- LOANS ----------
CREATE TABLE loans (
  loan_id     NUMBER DEFAULT seq_loan.NEXTVAL PRIMARY KEY,
  book_id     NUMBER NOT NULL,
  member_id   NUMBER NOT NULL,
  staff_id    NUMBER NOT NULL,
  loan_date   DATE   DEFAULT TRUNC(SYSDATE) NOT NULL,
  due_date    DATE   NOT NULL,
  return_date DATE,
  CONSTRAINT fk_loans_book   FOREIGN KEY (book_id)   REFERENCES books(book_id),
  CONSTRAINT fk_loans_member FOREIGN KEY (member_id) REFERENCES members(member_id),
  CONSTRAINT fk_loans_staff  FOREIGN KEY (staff_id)  REFERENCES staff(staff_id),
  CONSTRAINT ck_loans_due    CHECK (due_date >= loan_date),
  CONSTRAINT ck_loans_return CHECK (return_date IS NULL OR return_date >= loan_date)
);

-- ---------- FINES (1:1 with a late LOAN) ----------
CREATE TABLE fines (
  fine_id   NUMBER       DEFAULT seq_fine.NEXTVAL PRIMARY KEY,
  loan_id   NUMBER       NOT NULL,
  amount    NUMBER(8,2)  NOT NULL,
  paid      CHAR(1)      DEFAULT 'N' NOT NULL,
  paid_date DATE,
  CONSTRAINT uq_fines_loan   UNIQUE (loan_id),
  CONSTRAINT fk_fines_loan   FOREIGN KEY (loan_id) REFERENCES loans(loan_id),
  CONSTRAINT ck_fines_amount CHECK (amount > 0),
  CONSTRAINT ck_fines_paid   CHECK (paid IN ('Y','N'))
);

-- ---------- BOOK_AUDIT (filled by trigger) ----------
CREATE TABLE book_audit (
  audit_id    NUMBER        DEFAULT seq_audit.NEXTVAL PRIMARY KEY,
  book_id     NUMBER,
  action      VARCHAR2(10)  NOT NULL,
  old_title   VARCHAR2(200),
  new_title   VARCHAR2(200),
  changed_by  VARCHAR2(30)  DEFAULT USER NOT NULL,
  changed_at  TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

-- ---------- Indexes on foreign keys / frequent search columns ----------
CREATE INDEX ix_books_category  ON books(category_id);
CREATE INDEX ix_books_publisher ON books(publisher_id);
CREATE INDEX ix_books_title     ON books(UPPER(title));
CREATE INDEX ix_ba_author       ON book_authors(author_id);
CREATE INDEX ix_loans_member    ON loans(member_id);
CREATE INDEX ix_loans_book      ON loans(book_id);
CREATE INDEX ix_loans_open      ON loans(return_date, due_date);
