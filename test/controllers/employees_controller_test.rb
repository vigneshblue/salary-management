require "test_helper"

class EmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @in = Country.create!(name: "India", code: "IN", currency: "INR")
    @uk = Country.create!(name: "United Kingdom", code: "GB", currency: "GBP")

    @engineering = Department.create!(name: "Engineering")
    @product = Department.create!(name: "Product")
  end

  test "should get index and render employee list successfully" do
    Employee.create!(
      employee_number: "EMP001",
      name: "John Smith",
      country: @us,
      department: @engineering
    )

    get employees_url
    assert_response :success
    assert_select "h1.page-title", "Employees"
    assert_select "table.data-table"
    assert_select "td.employee-number", "EMP001"
    assert_select "td.employee-name", "John Smith"
  end

  test "displays employee details including country, department, and formatted current salary" do
    employee = Employee.create!(
      employee_number: "EMP002",
      name: "Arun Kumar",
      country: @in,
      department: @engineering
    )
    employee.salaries.create!(
      annual_salary: 1_200_000,
      effective_from: Date.new(2026, 1, 1)
    )

    get employees_url
    assert_response :success
    assert_select "td.employee-number", "EMP002"
    assert_select "td.employee-name", "Arun Kumar"
    assert_select "td.employee-country", "India"
    assert_select "td.employee-department", "Engineering"
    assert_select "td.employee-salary", text: /₹1,200,000/
  end

  test "determines current salary from the latest applicable salary record ordered by effective_from descending" do
    employee = Employee.create!(
      employee_number: "EMP003",
      name: "Priya Patel",
      country: @in,
      department: @product
    )

    # 1. Historical salary
    employee.salaries.create!(
      annual_salary: 800_000,
      effective_from: Date.current - 2.years
    )
    # 2. Latest applicable salary (effective now / past)
    employee.salaries.create!(
      annual_salary: 1_000_000,
      effective_from: Date.current - 3.months
    )
    # 3. Future salary raise scheduled for next month (not yet applicable)
    employee.salaries.create!(
      annual_salary: 1_500_000,
      effective_from: Date.current + 1.month
    )

    get employees_url
    assert_response :success

    # Current salary must be the latest applicable (1,000,000), not older (800,000) or future (1,500,000)
    assert_select "tr##{dom_id(employee)} td.employee-salary", text: /₹1,000,000/
    assert_select "tr##{dom_id(employee)} td.employee-salary", text: /1,500,000/, count: 0
  end

  test "displays clear fallback when employee has no salary record" do
    employee = Employee.create!(
      employee_number: "EMP004",
      name: "Emily Davis",
      country: @uk,
      department: @engineering
    )

    get employees_url
    assert_response :success
    assert_select "tr##{dom_id(employee)} td.employee-salary span.salary-fallback", "No salary record"
  end

  test "paginates employee list and does not load all employees into a single page" do
    25.times do |i|
      emp = Employee.create!(
        employee_number: format("EMP%04d", i + 1),
        name: "Worker #{i + 1}",
        country: @us,
        department: @engineering
      )
      emp.salaries.create!(annual_salary: 50_000 + (i * 1000), effective_from: Date.new(2026, 1, 1))
    end

    # Page 1
    get employees_url, params: { page: 1 }
    assert_response :success
    assert_select "tbody tr", count: 10
    assert_select "td.employee-number", "EMP0001"
    assert_select "td.employee-number", text: "EMP0011", count: 0
    assert_select ".pagination-info", text: /Showing 1 to 10 of 25 employees/
    assert_select "a.pagination-next"

    # Page 2
    get employees_url, params: { page: 2 }
    assert_response :success
    assert_select "tbody tr", count: 10
    assert_select "td.employee-number", "EMP0011"
    assert_select "td.employee-number", text: "EMP0001", count: 0
    assert_select ".pagination-info", text: /Showing 11 to 20 of 25 employees/
    assert_select "a.pagination-prev"
    assert_select "a.pagination-next"

    # Page 3 (remaining 5)
    get employees_url, params: { page: 3 }
    assert_response :success
    assert_select "tbody tr", count: 5
    assert_select "td.employee-number", "EMP0021"
    assert_select ".pagination-info", text: /Showing 21 to 25 of 25 employees/
  end

  test "avoids N+1 queries when rendering employees page" do
    15.times do |i|
      emp = Employee.create!(
        employee_number: format("EMP%04d", i + 1),
        name: "Employee #{i + 1}",
        country: (i.even? ? @us : @in),
        department: (i.even? ? @engineering : @product)
      )
      emp.salaries.create!(annual_salary: 60_000, effective_from: Date.current - 1.year)
      emp.salaries.create!(annual_salary: 70_000, effective_from: Date.current - 1.month)
    end

    query_count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      # Exclude schema / savepoint / transaction queries
      unless sql =~ /SCHEMA|PRAGMA|SHOW|TRANSACTION|SAVEPOINT/i
        query_count += 1
      end
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get employees_url
    end

    assert_response :success
    # Exactly: 1 COUNT(*) + 1 SELECT employees + 1 SELECT countries + 1 SELECT departments + 1 SELECT salaries = 5 queries
    assert_operator query_count, :<=, 6, "Expected at most 6 database queries, but performed #{query_count} (potential N+1 query detected)"
  end

  test "navigation sidebar includes link to Employees" do
    get employees_url
    assert_response :success
    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href='#{employees_path}']", text: /Employees/
    end
  end

  test "root path routes to employees#index" do
    get root_url
    assert_response :success
    assert_select "h1.page-title", "Employees"
  end
end
