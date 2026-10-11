# Employee Salary Management — Requirements

## 1. Goal

Build a web-based salary management system that enables ACME's HR Manager to manage employee salary information, process monthly salaries based on attendance, and understand how the organization pays its employees.

The system will replace the current spreadsheet-based workflow with a searchable and maintainable application capable of supporting approximately 10,000 employees across multiple countries.

## 2. User

**Primary user:** HR Manager

The application is designed for a single HR Manager persona. Authentication and authorization are not required for this assessment.

## 3. Scope & Features

### Employee Salary Management

The HR Manager can:

- View a paginated list of employees and their salary information.
- Search for employees.
- Filter employees by relevant attributes such as country and department.
- View employee details and salary information.
- Add and update employee and salary information.

### Monthly Salary Processing

The HR Manager can process monthly salaries based on employee attendance.

- Generate attendance data for employees for a selected month.
- View the generated attendance and calculated salary information.
- Salary remains **Pending** until it is processed.
- Process salaries for all eligible employees for the selected month.
- Mark processed salaries as **Paid**.
- Calculate monthly salary based on the employee's annual salary and attendance.
- View the salary processing status for a month.

Attendance generation is a controlled simulation for the assessment and may use randomly generated attendance data.

### Salary Insights

The application will help the HR Manager answer questions about how the organization pays its employees, such as:

- How many employees are there?
- How are employees distributed across countries?
- What are the salary ranges?
- What is the average salary?
- How does salary vary across countries and departments?
- How much salary was processed for a particular month?
- How many employees were paid for a particular month?
- How does total salary processed vary month over month?

The application will support employees across multiple countries and currencies. A common reporting currency may be used for cross-country salary comparisons using deterministic exchange rates.

## 4. Deliberately Out of Scope

- Authentication and authorization, as there is only one HR Manager persona.
- Creating, updating, or deleting employee records(except salary), as the assessment focuses on salary management rather than general employee lifecycle management.
- Tax and benefits management, as the assessment focuses on salary management rather than broader compensation.
- Salary processing in the application represents an internal payroll workflow and does not involve bank accounts or payment services.
- Payment dates and individual payment transactions. The application tracks the monthly salary processing status rather than actual financial transactions.
- Live currency exchange rate integration, as clarified by the assessment team, is not required. Deterministic exchange rates are sufficient for this assessment.
- Country management, including adding or updating countries and their exchange rates. The seed data will use a fixed set of five countries to demonstrate the multi-country salary management workflow.

These features are excluded to keep the assessment focused on the core salary management and monthly salary processing workflow.

## 5. Key Assumptions

- Salary represents the employee's annual salary.
- Employees may have different currencies based on their country.
- Monthly salary is derived from the employee's annual salary and attendance.
- Attendance is generated as simulated data for the assessment.
- Monthly salary starts in **Pending** status and becomes **Paid** when the HR Manager processes the salary.
- The application will support a dataset of approximately 10,000 employees.
- Authentication and authorization are not required.
- Live currency exchange rates are not required.
- The application is intended for use by an HR Manager.

## 6. Technical Approach

The application will be implemented as a Rails full-stack application using:

- Ruby on Rails
- Hotwire (Turbo and Stimulus)
- PostgreSQL

The application will include:

- A seed script containing 10,000 employees.
- Automated tests covering core functionality.
- Public deployment.
- Documentation covering setup, usage, and relevant design decisions.

## 7. Success Criteria

The solution will be considered successful when:

- An HR Manager can manage employee salary information through the web application.
- Employees and their salary information can be searched and filtered.
- Attendance can be generated for a selected month.
- Monthly salaries can be calculated based on attendance.
- Monthly salaries can be processed and marked as Paid.
- The application provides useful salary and monthly processing insights.
- The application works with a dataset of 10,000 employees.
- Core functionality is covered by fast and deterministic automated tests.
- The application is publicly deployed and usable end-to-end.
- The repository documents the requirements, approach, and relevant design decisions.