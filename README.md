# ACME HR — Employee Salary & Attendance Management

A Ruby on Rails application for HR managers to manage employee records, salary history, monthly attendance, simulated salary processing, and multi-currency reporting.

**Live demo:** https://salary-management-1v23.onrender.com  
**Stack:** Ruby on Rails 8.1.4 · Ruby 4.0.6 · PostgreSQL · Hotwire

> This is an assignment/demo application. It does not process real payments and should not be used with real employee data because authentication and authorization are not implemented.

## Table of Contents

1. [Features](#features)
2. [Technology Stack](#technology-stack)
3. [Prerequisites](#prerequisites)
4. [Local Setup](#local-setup)
5. [Seed Data](#seed-data)
6. [Business Rules](#business-rules)
7. [Tests and Code Quality](#tests-and-code-quality)
8. [Deployment](#deployment)
9. [Architecture](#architecture)
10. [Known Limitations](#known-limitations)

## Features

- **Employee directory:** Search by employee number or name, filter by country and department, and browse paginated results.
- **Employee management:** Create and edit employee records, including country, department, and joining date.
- **Salary history:** Record salary changes with effective dates while preserving earlier salary records.
- **Attendance:** Generate monthly weekday attendance records with deterministic attendance values and joining-date eligibility.
- **Monthly salary calculations:** Calculate monthly base salary and attendance-based payable salary.
- **Simulated salary processing:** Change pending salary records to paid for a selected period. No bank transfer is initiated.
- **Paginated records:** Browse and filter attendance and monthly salary records.
- **Dashboard:** View workforce and salary insights, with illustrative conversion to a selected reporting currency.

## Technology Stack

- **Backend:** Ruby on Rails 8.1.4
- **Ruby:** 4.0.6, as specified in `.ruby-version`
- **Database:** PostgreSQL
- **Frontend:** Hotwire (Turbo Rails and Stimulus Rails), with Import Maps
- **Assets:** Propshaft
- **Application server:** Puma
- **Container/deployment configuration:** Render
- **Code quality/security tools:** RuboCop, Brakeman, and Bundler Audit

## Prerequisites

Install the following before setting up the application:

- Ruby 4.0.6
- Bundler
- PostgreSQL 14 or later
- Git
- Required system libraries for your operating system, including PostgreSQL development headers and `libvips` if required by the installed dependencies

## Local Setup

### 1. Clone the repository

Replace `<repository-url>` with the repository URL.

```bash
git clone <repository-url> salary-management
cd salary-management
```

### 2. Install dependencies

```bash
bundle install
```

### 3. Configure PostgreSQL

Check `config/database.yml` and configure a local PostgreSQL user/database that matches its settings, or configure a supported connection URL.

If your local setup uses the default credentials shown in `config/database.yml`, make sure those credentials exist in PostgreSQL before continuing.

### 4. Create and prepare the database

```bash
bin/rails db:prepare
bin/rails db:seed
```

`db:prepare` creates the database when needed and applies migrations. The seed command creates the reference and sample data.

### 5. Start the server

```bash
bin/rails server
```

Open [http://localhost:3000](http://localhost:3000).

## Seed Data

The seed script is designed to create a deterministic sample dataset. The documented dataset includes:

- **10,000 employees**, numbered `EMP00001` through `EMP10000`
- **Five countries:** India (INR), United States (USD), United Kingdom (GBP), Canada (CAD), and Australia (AUD)
- **Seven departments:** Engineering, Sales, Operations, Marketing, Product, Finance, and Human Resources
- Joining dates distributed across approximately the past five years
- Salary history records with effective dates constrained by employee joining dates

The seed implementation uses upsert operations and database uniqueness constraints to help avoid duplicate records when seeds are run repeatedly. Confirm the exact seeded counts against `db/seeds.rb` if you change the seed configuration.

## Business Rules

### Attendance

- Working days are Monday through Friday; public holidays are not excluded.
- Employees who join during a month are eligible only from their joining date through the end of that month.
- Employees who join after the selected month receive zero eligible, present, and absent days for that period.
- Present-day generation is deterministic for a given employee and period.
- Attendance generation is designed to be repeatable without creating duplicate records.

### Salary calculation

- Monthly base salary is the applicable annual salary divided by 12, rounded to two decimal places.
- The applicable salary is the latest salary record whose `effective_from` date is on or before the first day of the selected month.
- Payable salary is calculated using eligible working days and present days:

  `payable_amount = monthly_base * present_days / eligible_working_days`

- The payable amount is rounded to two decimal places.
- If eligible working days or present days are zero, the payable amount is zero.
- Employees who joined after the selected month receive zero payable salary for that period.
- Newly generated monthly salary records with `payable_amount > 0` start with `Pending` status.
- Monthly salary records with `payable_amount <= 0` (e.g. post-month joiners or zero present days) are assigned `Not Payable` status.

### Salary processing

- Processing changes eligible `Pending` records with `payable_amount > 0` to `Paid` for the selected period.
- Records with `Not Payable` status are never marked `Paid`.
- Legacy zero-value `Pending` records are automatically transitioned to `Not Payable` instead of being paid.
- The operation is performed in a database transaction with row locking.
- This is a simulation only; no external payment provider or bank transfer is involved.

### Currency reporting

- Compensation is stored in each employee's country currency.
- Amounts in different currencies should not be added together without conversion.
- Dashboard conversion uses fixed illustrative rates benchmarked against INR, not live market rates:
  - USD: 83 INR
  - GBP: 105 INR
  - CAD: 61 INR
  - AUD: 54 INR
  - INR: 1 INR

These rates are examples for reporting and should not be used for financial decisions.

## Tests and Code Quality

Run the full test suite:

```bash
bin/rails test
```

Run focused tests as needed. Confirm these paths exist in the current repository before using them:

```bash
bin/rails test test/controllers/employees_controller_test.rb
bin/rails test test/controllers/attendances_controller_test.rb
bin/rails test test/controllers/monthly_salaries_controller_test.rb
bin/rails test test/services/joining_date_test.rb
```

Run code quality and security tools if installed in the bundle:

```bash
bundle exec rubocop
bundle exec brakeman
bundle exec bundle-audit
```

Most recently reported test result during development: **194 runs, 1,136 assertions, 0 failures, 0 errors, 0 skips**. Re-run the suite after any changes before relying on this result for a submission.

## Deployment

The application is deployed on **Render** and uses PostgreSQL for persistent application data.

Common production settings include:

| Variable | Purpose |
|---|---|
| `RAILS_MASTER_KEY` | Decrypts encrypted Rails credentials |
| `SECRET_KEY_BASE` | Alternative secret configuration where supported |
| `DATABASE_URL` | PostgreSQL connection URL |
| `RAILS_MAX_THREADS` | Puma/database thread pool sizing |
| `WEB_CONCURRENCY` | Puma worker process count |

Use the configuration and deployment platform actually selected for the assignment. The live demo link above is provided for evaluation; availability may depend on the hosting platform's current state.

## Architecture

The application separates HTTP handling, persistence, and business logic:

- **Controllers:** Employee, attendance, dashboard, and monthly salary request handling.
- **Models:** Employees, countries, departments, periods, salaries, attendance, and monthly salary records.
- **Services:** Attendance generation, salary calculation, salary processing, currency conversion, and salary insights.
- **Views:** Rails ERB templates with Hotwire interactions and reusable pagination.
- **Database:** PostgreSQL with migrations, indexes, and uniqueness constraints.
- **Tests:** Rails tests for application behavior and business rules.

## Known Limitations

- **No authentication or authorization:** The application is intended for assignment evaluation, not production use with real employee data.
- **Simulated payments:** Marking salaries as paid does not transfer money.
- **Fixed exchange rates:** Reporting conversion is illustrative and not updated from a live exchange-rate service.
- **No taxes or statutory deductions:** Calculations do not include income tax, retirement contributions, benefits, or other deductions.
- **No public-holiday calendar:** Attendance excludes weekends only.
- **No employee self-service or approval workflow:** The application focuses on HR-manager workflows.
