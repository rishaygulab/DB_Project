rem
rem Copyright (c) 2023 Oracle
rem
rem Permission is hereby granted, free of charge, to any person obtaining a
rem copy of this software and associated documentation files (the "Software"),
rem to deal in the Software without restriction, including without limitation
rem the rights to use, copy, modify, merge, publish, distribute, sublicense,
rem and/or sell copies of the Software, and to permit persons to whom the
rem Software is furnished to do so, subject to the following conditions:
rem
rem The above copyright notice and this permission notice shall be included in
rem all copies or substantial portions rem of the Software.
rem 
rem THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
rem IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
rem FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
rem THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
rem LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
rem FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
rem DEALINGS IN THE SOFTWARE.
rem
rem NAME
rem   hr_create.sql - Creates schema objects for HR (Human Resources) schema
rem
rem DESCRIPTION
rem   This script creates tables, associated constraints,
rem      indexes, and comments in the HR schema.
rem
rem SCHEMA VERSION
rem   21
rem
rem RELEASE DATE
rem   03-FEB-2022
rem
rem SUPPORTED with DB VERSIONS
rem   19c and higher
rem 
rem MAJOR CHANGES IN THIS RELEASE
rem   
rem
rem SCHEMA DEPENDENCIES AND REQUIREMENTS
rem   This script is called from the hr_install.sql script
rem 
rem INSTALL INSTRUCTIONS
rem    Run the hr_install.sql script to call this script
rem 
rem --------------------------------------------------------------------------

-- MariaDB 11.8 port (sql_mode=ORACLE): every change is marked '-- MIGRATION:'.
-- See migration/COMPATIBILITY_MATRIX.md (HR section).

SET FEEDBACK 1
SET NUMWIDTH 10
SET LINESIZE 80
SET TRIMSPOOL ON
SET TAB OFF
SET PAGESIZE 100
SET ECHO OFF 

rem ********************************************************************
rem Create the REGIONS table to hold region information for locations
rem HR.LOCATIONS table has a foreign key to this table.

Prompt ******  Creating REGIONS table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE regions
    ( region_id      NUMBER 
       NOT NULL COMMENT 'Primary key of regions table.'
    , region_name    VARCHAR2(25) COMMENT 'Names of regions. Locations are in the countries of these regions.'
    );

-- MIGRATION: unique index reg_id_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX reg_id_pk
-- ON regions (region_id);

ALTER TABLE regions
ADD ( CONSTRAINT reg_id_pk
       		 PRIMARY KEY (region_id)
    ) ;

rem ********************************************************************
rem Create the COUNTRIES table to hold country information for customers
rem and company locations.
rem OE.CUSTOMERS table and HR.LOCATIONS have a foreign key to this table.

Prompt ******  Creating COUNTRIES table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE countries 
    ( country_id      CHAR(2) 
       NOT NULL COMMENT 'Primary key of countries table.'
    , country_name    VARCHAR2(60) COMMENT 'Country name'
    , region_id       NUMBER COMMENT 'Region ID for the country. Foreign key to region_id column in the departments table.'
    , CONSTRAINT     country_c_id_pk 
        	     PRIMARY KEY (country_id) 
    ) 
    -- MIGRATION: ORGANIZATION INDEX removed (syntax error, probe T14). InnoDB tables are
    --   always clustered on the primary key, so the storage is already index-organized.
    -- ORGANIZATION INDEX
    ;

ALTER TABLE countries
ADD ( CONSTRAINT countr_reg_fk
        	 FOREIGN KEY (region_id)
          	  REFERENCES regions(region_id) 
    ) ;

rem ********************************************************************
rem Create the LOCATIONS table to hold address information for company departments.
rem HR.DEPARTMENTS has a foreign key to this table.

Prompt ******  Creating LOCATIONS table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE locations
    ( location_id    NUMBER(4) COMMENT 'Primary key of locations table'
    , street_address VARCHAR2(40) COMMENT 'Street address of an office, warehouse, or production site of a company.
Contains building number and street name'
    , postal_code    VARCHAR2(12) COMMENT 'Postal code of the location of an office, warehouse, or production site 
of a company. '
    , city       VARCHAR2(30)
	NOT NULL COMMENT 'A not null column that shows city where an office, warehouse, or 
production site of a company is located. '
    , state_province VARCHAR2(25) COMMENT 'State or Province where an office, warehouse, or production site of a 
company is located.'
    , country_id     CHAR(2) COMMENT 'Country where an office, warehouse, or production site of a company is
located. Foreign key to country_id column of the countries table.'
    ) ;

-- MIGRATION: unique index loc_id_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX loc_id_pk
-- ON locations (location_id) ;

ALTER TABLE locations
ADD ( CONSTRAINT loc_id_pk
       		 PRIMARY KEY (location_id)
    , CONSTRAINT loc_c_id_fk
       		 FOREIGN KEY (country_id)
        	  REFERENCES countries(country_id) 
    ) ;

Rem 	Useful for any subsequent addition of rows to locations table
Rem 	Starts with 3300

CREATE SEQUENCE locations_seq
 START WITH     3300
 INCREMENT BY   100
 MAXVALUE       9900
 NOCACHE
 NOCYCLE;

rem ********************************************************************
rem Create the DEPARTMENTS table to hold company department information.
rem HR.EMPLOYEES and HR.JOB_HISTORY have a foreign key to this table.

Prompt ******  Creating DEPARTMENTS table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE departments
    ( department_id    NUMBER(4) COMMENT 'Primary key column of departments table.'
    , department_name  VARCHAR2(30)
	NOT NULL COMMENT 'A not null column that shows name of a department. Administration, 
Marketing, Purchasing, Human Resources, Shipping, IT, Executive, Public 
Relations, Sales, Finance, and Accounting. '
    , manager_id       NUMBER(6) COMMENT 'Manager_id of a department. Foreign key to employee_id column of employees table. The manager_id column of the employee table references this column.'
    , location_id      NUMBER(4) COMMENT 'Location id where a department is located. Foreign key to location_id column of locations table.'
    ) ;

-- MIGRATION: unique index dept_id_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX dept_id_pk
-- ON departments (department_id) ;

ALTER TABLE departments
ADD ( CONSTRAINT dept_id_pk
       		 PRIMARY KEY (department_id)
    , CONSTRAINT dept_loc_fk
       		 FOREIGN KEY (location_id)
        	  REFERENCES locations (location_id)
     ) ;

Rem 	Useful for any subsequent addition of rows to departments table
Rem 	Starts with 280 

CREATE SEQUENCE departments_seq
 START WITH     280
 INCREMENT BY   10
 MAXVALUE       9990
 NOCACHE
 NOCYCLE;

rem ********************************************************************
rem Create the JOBS table to hold the different names of job roles within the company.
rem HR.EMPLOYEES has a foreign key to this table.

Prompt ******  Creating JOBS table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE jobs
    ( job_id         VARCHAR2(10) COMMENT 'Primary key of jobs table.'
    , job_title      VARCHAR2(35)
	NOT NULL COMMENT 'A not null column that shows job title, e.g. AD_VP, FI_ACCOUNTANT'
    , min_salary     NUMBER(6) COMMENT 'Minimum salary for a job title.'
    , max_salary     NUMBER(6) COMMENT 'Maximum salary for a job title'
    ) ;

-- MIGRATION: unique index job_id_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX job_id_pk 
-- ON jobs (job_id) ;

ALTER TABLE jobs
ADD ( CONSTRAINT job_id_pk
      		 PRIMARY KEY(job_id)
    ) ;

rem ********************************************************************
rem Create the EMPLOYEES table to hold the employee personnel
rem information for the company.
rem HR.EMPLOYEES has a self referencing foreign key to this table.

Prompt ******  Creating EMPLOYEES table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE employees
    ( employee_id    NUMBER(6) COMMENT 'Primary key of employees table.'
    , first_name     VARCHAR2(20) COMMENT 'First name of the employee. A not null column.'
    , last_name      VARCHAR2(25)
	 NOT NULL COMMENT 'Last name of the employee. A not null column.'
    , email          VARCHAR2(25)
	NOT NULL COMMENT 'Email id of the employee'
    , phone_number   VARCHAR2(20) COMMENT 'Phone number of the employee; includes country code and area code'
    , hire_date      DATE
	NOT NULL COMMENT 'Date when the employee started on this job. A not null column.'
    , job_id         VARCHAR2(10)
	NOT NULL COMMENT 'Current job of the employee; foreign key to job_id column of the 
jobs table. A not null column.'
    , salary         NUMBER(8,2) COMMENT 'Monthly salary of the employee. Must be greater 
than zero (enforced by constraint emp_salary_min)'
    , commission_pct NUMBER(2,2) COMMENT 'Commission percentage of the employee; Only employees in sales 
department elgible for commission percentage'
    , manager_id     NUMBER(6) COMMENT 'Manager id of the employee; has same domain as manager_id in 
departments table. Foreign key to employee_id column of employees table. 
(useful for reflexive joins and CONNECT BY query)'
    , department_id  NUMBER(4) COMMENT 'Department id where employee works; foreign key to department_id 
column of the departments table'
    , CONSTRAINT     emp_salary_min
                     CHECK (salary > 0) 
    , CONSTRAINT     emp_email_uk
                     UNIQUE (email)
    ) ;

-- MIGRATION: unique index emp_emp_id_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX emp_emp_id_pk
-- ON employees (employee_id) ;


-- MIGRATION: PRIMARY KEY added in its own ALTER (InnoDB rejects the self-referencing
--   emp_manager_fk with errno 150 when the PK it points to is added in the same statement)
ALTER TABLE employees
ADD ( CONSTRAINT     emp_emp_id_pk
                     PRIMARY KEY (employee_id)
    ) ;

ALTER TABLE employees
ADD ( CONSTRAINT     emp_dept_fk
                     FOREIGN KEY (department_id)
                      REFERENCES departments (department_id) -- MIGRATION: PK column named (T16)
    , CONSTRAINT     emp_job_fk
                     FOREIGN KEY (job_id)
                      REFERENCES jobs (job_id)
    , CONSTRAINT     emp_manager_fk
                     FOREIGN KEY (manager_id)
                      REFERENCES employees (employee_id) -- MIGRATION: PK column named (T16)
    ) ;

ALTER TABLE departments
ADD ( CONSTRAINT dept_mgr_fk
      		 FOREIGN KEY (manager_id)
      		  REFERENCES employees (employee_id)
    ) ;


Rem 	Useful for any subsequent addition of rows to employees table
Rem 	Starts with 207 


CREATE SEQUENCE employees_seq
 START WITH     207
 INCREMENT BY   1
 NOCACHE
 NOCYCLE;

rem ********************************************************************
rem Create the JOB_HISTORY table to hold the history of jobs that
rem employees have held in the past.
rem HR.JOBS, HR_DEPARTMENTS, and HR.EMPLOYEES have a foreign key to this table.

Prompt ******  Creating JOB_HISTORY table ....

-- MIGRATION: inline 'CONSTRAINT <name> NOT NULL' -> 'NOT NULL' (named NOT NULL
--   constraints are a syntax error, probe T13); column comments moved inline (T20).
CREATE TABLE job_history
    ( employee_id   NUMBER(6)
	 NOT NULL COMMENT 'A not null column in the complex primary key employee_id+start_date. 
Foreign key to employee_id column of the employee table'
    , start_date    DATE
	NOT NULL COMMENT 'A not null column in the complex primary key employee_id+start_date. 
Must be less than the end_date of the job_history table. (enforced by 
constraint jhist_date_interval)'
    , end_date      DATE
	NOT NULL COMMENT 'Last day of the employee in this job role. A not null column. Must be 
greater than the start_date of the job_history table. 
(enforced by constraint jhist_date_interval)'
    , job_id        VARCHAR2(10)
	NOT NULL COMMENT 'Job role in which the employee worked in the past; foreign key to 
job_id column in the jobs table. A not null column.'
    , department_id NUMBER(4) COMMENT 'Department id in which the employee worked in the past; foreign key to deparment_id column in the departments table'
    , CONSTRAINT    jhist_date_interval
                    CHECK (end_date > start_date)
    ) ;

-- MIGRATION: unique index jhist_emp_id_st_date_pk removed: the PRIMARY KEY below cannot reuse it, so it
--   would be a second, duplicate index (probe T15). InnoDB names the PK 'PRIMARY'.
-- CREATE UNIQUE INDEX jhist_emp_id_st_date_pk 
-- ON job_history (employee_id, start_date) ;

ALTER TABLE job_history
ADD ( CONSTRAINT jhist_emp_id_st_date_pk
      PRIMARY KEY (employee_id, start_date)
    , CONSTRAINT     jhist_job_fk
                     FOREIGN KEY (job_id)
                     REFERENCES jobs (job_id) -- MIGRATION: PK column named (T16)
    , CONSTRAINT     jhist_emp_fk
                     FOREIGN KEY (employee_id)
                     REFERENCES employees (employee_id) -- MIGRATION: PK column named (T16)
    , CONSTRAINT     jhist_dept_fk
                     FOREIGN KEY (department_id)
                     REFERENCES departments (department_id) -- MIGRATION: PK column named (T16)
    ) ;

rem ********************************************************************
rem Create the EMP_DETAILS_VIEW that joins the employees, jobs,
rem departments, jobs, countries, and locations table to provide details
rem about employees.

Prompt ******  Creating EMP_DETAILS_VIEW view ...

-- MIGRATION: WITH READ ONLY -> ALGORITHM=TEMPTABLE (syntax error, probe D4). Without it this
--   join view is updatable in MariaDB; TEMPTABLE makes UPDATE/INSERT/DELETE fail (error 1288
--   instead of ORA-42399). Cost: the view is materialized per query instead of merged.
CREATE OR REPLACE ALGORITHM=TEMPTABLE VIEW emp_details_view
  (employee_id,
   job_id,
   manager_id,
   department_id,
   location_id,
   country_id,
   first_name,
   last_name,
   salary,
   commission_pct,
   department_name,
   job_title,
   city,
   state_province,
   country_name,
   region_name)
AS SELECT
  e.employee_id, 
  e.job_id, 
  e.manager_id, 
  e.department_id,
  d.location_id,
  l.country_id,
  e.first_name,
  e.last_name,
  e.salary,
  e.commission_pct,
  d.department_name,
  j.job_title,
  l.city,
  l.state_province,
  c.country_name,
  r.region_name
FROM
  employees e,
  departments d,
  jobs j,
  locations l,
  countries c,
  regions r
WHERE e.department_id = d.department_id
  AND d.location_id = l.location_id
  AND l.country_id = c.country_id
  AND c.region_id = r.region_id
  AND j.job_id = e.job_id 
-- WITH READ ONLY
;

rem ********************************************************************
rem Create indexes

Prompt ******  Creating indexes ...

CREATE INDEX emp_department_ix
       ON employees (department_id);

CREATE INDEX emp_job_ix
       ON employees (job_id);

CREATE INDEX emp_manager_ix
       ON employees (manager_id);

CREATE INDEX emp_name_ix
       ON employees (last_name, first_name);

CREATE INDEX dept_location_ix
       ON departments (location_id);

CREATE INDEX jhist_job_ix
       ON job_history (job_id);

CREATE INDEX jhist_employee_ix
       ON job_history (employee_id);

CREATE INDEX jhist_department_ix
       ON job_history (department_id);

CREATE INDEX loc_city_ix
       ON locations (city);

CREATE INDEX loc_state_province_ix	
       ON locations (state_province);

CREATE INDEX loc_country_ix
       ON locations (country_id);


rem ********************************************************************
rem Add table column comments

Prompt ******  Adding table column comments ...

-- MIGRATION: COMMENT ON TABLE -> ALTER TABLE ... COMMENT = (no COMMENT ON, probe T20);
--   COMMENT ON COLUMN statements moved into the CREATE TABLE column definitions above.

ALTER TABLE regions COMMENT = 'Regions table that contains region numbers and names. references with the Countries table.';



ALTER TABLE locations COMMENT = 'Locations table that contains specific address of a specific office,
warehouse, and/or production site of a company. Does not store addresses /
locations of customers. references with the departments and countries tables. ';








rem *********************************************

ALTER TABLE departments COMMENT = 'Departments table that shows details of departments where employees 
work. references with locations, employees, and job_history tables.';






rem *********************************************

ALTER TABLE job_history COMMENT = 'Table that stores job history of the employees. If an employee 
changes departments within the job or changes jobs within the department, 
new rows get inserted into this table with old job information of the 
employee. Contains a complex primary key: employee_id+start_date.
References with jobs, employees, and departments tables.';






rem *********************************************

ALTER TABLE countries COMMENT = 'country table. References with locations table.';




rem *********************************************

ALTER TABLE jobs COMMENT = 'jobs table with job titles and salary ranges.
References with employees and job_history table.';





rem *********************************************

ALTER TABLE employees COMMENT = 'employees table. References with departments,
jobs, job_history tables. Contains a self reference.';











