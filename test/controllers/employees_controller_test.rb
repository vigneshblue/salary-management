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
    # Queries breakdown:
    #   1 COUNT(*) for pagination
    #   1 SELECT employees (paginated)
    #   1 SELECT countries (eager load for employee rows)
    #   1 SELECT departments (eager load for employee rows)
    #   1 SELECT salaries (eager load for employee rows)
    #   1 SELECT countries (for dropdown population)
    #   1 SELECT departments (for dropdown population)
    # = 7 queries (plus up to 2 transaction-related): cap at 9
    assert_operator query_count, :<=, 9, "Expected at most 9 database queries, but performed #{query_count} (potential N+1 query detected)"
  end

  test "navigation sidebar includes link to Employees" do
    get employees_url
    assert_response :success
    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href='#{employees_path}']", text: /Employees/
    end
  end

  test "root path routes to dashboards#show" do
    get root_url
    assert_response :success
    assert_select "h1.page-title", "Salary Insights Dashboard"
  end

  # =====================
  # Search and Filter Tests
  # =====================

  test "search by employee number returns matching employees only" do
    emp_a = Employee.create!(employee_number: "EMP100", name: "Alice Adams", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP200", name: "Bob Barnes", country: @in, department: @product)

    get employees_url, params: { q: "EMP100" }
    assert_response :success
    assert_select "td.employee-number", "EMP100"
    assert_select "td.employee-number", text: "EMP200", count: 0
    assert_select "tbody tr", count: 1
  end

  test "search by employee name returns matching employees only" do
    Employee.create!(employee_number: "EMP101", name: "Alice Adams", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP102", name: "Bob Barnes", country: @in, department: @product)

    get employees_url, params: { q: "Alice" }
    assert_response :success
    assert_select "td.employee-name", "Alice Adams"
    assert_select "td.employee-name", text: "Bob Barnes", count: 0
  end

  test "search is case insensitive" do
    Employee.create!(employee_number: "EMP103", name: "Charlie Chen", country: @us, department: @engineering)

    get employees_url, params: { q: "charlie chen" }
    assert_response :success
    assert_select "td.employee-name", "Charlie Chen"
  end

  test "partial search matches both name and employee number" do
    Employee.create!(employee_number: "EMP104", name: "David Dean", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP105", name: "Eva Evans", country: @in, department: @product)

    get employees_url, params: { q: "EMP10" }
    assert_response :success
    assert_select "tbody tr", count: 2
    assert_select "td.employee-number", "EMP104"
    assert_select "td.employee-number", "EMP105"
  end

  test "filter by country returns only employees from that country" do
    Employee.create!(employee_number: "EMP110", name: "Frank Ford", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP111", name: "Grace Gupta", country: @in, department: @product)

    get employees_url, params: { country_id: @us.id }
    assert_response :success
    assert_select "td.employee-country", "United States"
    assert_select "td.employee-country", text: "India", count: 0
  end

  test "filter by department returns only employees in that department" do
    Employee.create!(employee_number: "EMP120", name: "Hank Hill", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP121", name: "Iris Ingram", country: @us, department: @product)

    get employees_url, params: { department_id: @engineering.id }
    assert_response :success
    assert_select "td.employee-department", "Engineering"
    assert_select "td.employee-department", text: "Product", count: 0
  end

  test "search and country filter work together" do
    Employee.create!(employee_number: "EMP130", name: "Jack Jones", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP131", name: "Jack Kumar", country: @in, department: @engineering)

    get employees_url, params: { q: "Jack", country_id: @us.id }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "td.employee-name", "Jack Jones"
    assert_select "td.employee-name", text: "Jack Kumar", count: 0
  end

  test "search and department filter work together" do
    Employee.create!(employee_number: "EMP140", name: "Kate King", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP141", name: "Kate Lee", country: @us, department: @product)

    get employees_url, params: { q: "Kate", department_id: @engineering.id }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "td.employee-name", "Kate King"
    assert_select "td.employee-name", text: "Kate Lee", count: 0
  end

  test "all three filters work combined" do
    Employee.create!(employee_number: "EMP150", name: "Liam Lee", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP151", name: "Liam Lin", country: @in, department: @engineering)
    Employee.create!(employee_number: "EMP152", name: "Liam Long", country: @us, department: @product)

    get employees_url, params: { q: "Liam", country_id: @us.id, department_id: @engineering.id }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "td.employee-name", "Liam Lee"
  end

  test "search with no matching employees shows contextual empty state" do
    get employees_url, params: { q: "ZZZNONEXISTENT" }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "td.empty-state", text: /No employees match your search or filters/
  end

  test "filter with no matching employees shows contextual empty state" do
    get employees_url, params: { country_id: @uk.id }
    assert_response :success
    assert_select "td.empty-state", text: /No employees match your search or filters/
  end

  test "pagination preserves search params in next/prev links" do
    15.times do |i|
      Employee.create!(
        employee_number: format("SRCH%04d", i + 1),
        name: "Searchable Person #{i + 1}",
        country: @us,
        department: @engineering
      )
    end

    get employees_url, params: { q: "Searchable", page: 1 }
    assert_response :success
    assert_select "tbody tr", count: 10
    assert_select ".pagination-info", text: /Showing 1 to 10 of 15 employees/
    # Next page link must include the search param
    assert_select "a.pagination-next[href*='q=Searchable']"

    get employees_url, params: { q: "Searchable", page: 2 }
    assert_response :success
    assert_select "tbody tr", count: 5
    assert_select ".pagination-info", text: /Showing 11 to 15 of 15 employees/
    # Previous page link must include the search param
    assert_select "a.pagination-prev[href*='q=Searchable']"
  end

  test "pagination preserves country filter in links" do
    12.times do |i|
      Employee.create!(
        employee_number: format("FILT%04d", i + 1),
        name: "Filter Person #{i + 1}",
        country: @us,
        department: @engineering
      )
    end

    get employees_url, params: { country_id: @us.id, page: 1 }
    assert_response :success
    assert_select "a.pagination-next[href*='country_id=#{@us.id}']"
  end

  test "search renders the search and filter UI controls" do
    get employees_url
    assert_response :success
    assert_select "form.search-bar"
    assert_select "input.search-input"
    assert_select "select.filter-select", count: 2
    assert_select "input.btn-primary[type='submit']"
  end

  # =====================
  # Employee Details Tests
  # =====================

  test "should show employee details successfully" do
    employee = Employee.create!(
      employee_number: "EMP999",
      name: "Detail Tester",
      country: @us,
      department: @engineering
    )

    get employee_url(employee)
    assert_response :success
    assert_select "h1.page-title", "Detail Tester"
    assert_select ".employee-number", "EMP999"
    assert_select ".employee-country", "United States"
    assert_select ".employee-department", "Engineering"
  end

  test "show displays salary history ordered by effective_from DESC" do
    employee = Employee.create!(
      employee_number: "EMP888",
      name: "Salary Tester",
      country: @in,
      department: @product
    )

    employee.salaries.create!(annual_salary: 800_000, effective_from: Date.new(2023, 1, 1))
    employee.salaries.create!(annual_salary: 1_200_000, effective_from: Date.new(2025, 1, 1))
    employee.salaries.create!(annual_salary: 1_000_000, effective_from: Date.new(2024, 1, 1))

    get employee_url(employee)
    assert_response :success

    # Check that current salary correctly grabs the latest applicable
    assert_select ".employee-current-salary", text: /1,200,000/

    # Check history ordering
    assert_select "td.salary-amount" do |elements|
      amounts = elements.map(&:text)
      # Should be ordered DESC by date, so 2025, then 2024, then 2023
      assert_match(/1,200,000/, amounts[0])
      assert_match(/1,000,000/, amounts[1])
      assert_match(/800,000/, amounts[2])
    end
  end

  test "show displays fallback when employee has no salary records" do
    employee = Employee.create!(
      employee_number: "EMP777",
      name: "No Salary Tester",
      country: @uk,
      department: @engineering
    )

    get employee_url(employee)
    assert_response :success
    assert_select "td.empty-state", text: /No salary records found/
    assert_select ".employee-current-salary span.salary-fallback", "No salary record"
  end

  test "show returns 404 for unknown employee ID" do
    get employee_url(-1)
    assert_response :not_found
  end

  test "avoids N+1 queries on the show page" do
    employee = Employee.create!(
      employee_number: "EMP666",
      name: "Performance Tester",
      country: @us,
      department: @engineering
    )
    employee.salaries.create!(annual_salary: 60_000, effective_from: Date.current - 1.year)
    employee.salaries.create!(annual_salary: 70_000, effective_from: Date.current - 1.month)

    query_count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      unless sql =~ /SCHEMA|PRAGMA|SHOW|TRANSACTION|SAVEPOINT/i
        query_count += 1
      end
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get employee_url(employee)
    end

    assert_response :success
    # 1 Employee query, 1 Country query (eager), 1 Department query (eager), 1 Salaries query (for @salaries)
    assert_operator query_count, :<=, 5, "Expected at most 5 database queries on show page"
  end

  # =====================
  # Add Employee Tests
  # =====================

  test "new employee form renders and dropdowns are populated" do
    get new_employee_url
    assert_response :success
    assert_select "h1.page-title", "Add Employee"
    assert_select "form[action='#{employees_path}']"
    assert_select "input[name='employee[employee_number]']"
    assert_select "input[name='employee[name]']"
    assert_select "select[name='employee[country_id]']" do
      assert_select "option", text: "United States"
      assert_select "option", text: "India"
    end
    assert_select "select[name='employee[department_id]']" do
      assert_select "option", text: "Engineering"
      assert_select "option", text: "Product"
    end
    assert_select "input[name='employee[initial_salary]']"
    assert_select "input[name='employee[salary_effective_from]']"
  end

  test "index page includes clear Add Employee button" do
    get employees_url
    assert_response :success
    assert_select "a.btn-primary[href='#{new_employee_path}']", text: "Add Employee"
  end

  test "valid employee creation creates both Employee and initial Salary records in one transaction" do
    assert_difference -> { Employee.count } => 1, -> { Salary.count } => 1 do
      post employees_url, params: {
        employee: {
          employee_number: "EMP500",
          name: "Grace Hopper",
          country_id: @us.id,
          department_id: @engineering.id,
          initial_salary: "120000",
          salary_effective_from: Date.new(2026, 1, 1).to_s
        }
      }
    end

    created_employee = Employee.find_by!(employee_number: "EMP500")
    assert_redirected_to employee_path(created_employee)
    follow_redirect!
    assert_select ".alert-success", text: /Employee created successfully/

    assert_equal 1, created_employee.salaries.count
    initial_salary = created_employee.salaries.first
    assert_equal 120_000.to_d, initial_salary.annual_salary
    assert_equal Date.new(2026, 1, 1), initial_salary.effective_from
  end

  test "invalid employee data creates neither employee nor salary record" do
    assert_no_difference [ "Employee.count", "Salary.count" ] do
      post employees_url, params: {
        employee: {
          employee_number: "",
          name: "Invalid Employee",
          country_id: @us.id,
          department_id: @engineering.id,
          initial_salary: "100000",
          salary_effective_from: Date.new(2026, 1, 1).to_s
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1.page-title", "Add Employee"
    assert_select ".alert-danger", text: /can't be blank/
  end

  test "missing or invalid salary data creates neither employee nor salary record" do
    # Missing salary
    assert_no_difference [ "Employee.count", "Salary.count" ] do
      post employees_url, params: {
        employee: {
          employee_number: "EMP501",
          name: "No Salary",
          country_id: @us.id,
          department_id: @engineering.id,
          initial_salary: "",
          salary_effective_from: Date.new(2026, 1, 1).to_s
        }
      }
    end
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /can't be blank/
    assert_nil Employee.find_by(employee_number: "EMP501")

    # Negative salary
    assert_no_difference [ "Employee.count", "Salary.count" ] do
      post employees_url, params: {
        employee: {
          employee_number: "EMP502",
          name: "Negative Salary",
          country_id: @us.id,
          department_id: @engineering.id,
          initial_salary: "-500",
          salary_effective_from: Date.new(2026, 1, 1).to_s
        }
      }
    end
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /must be greater than or equal to 0/
    assert_nil Employee.find_by(employee_number: "EMP502")

    # Missing effective date
    assert_no_difference [ "Employee.count", "Salary.count" ] do
      post employees_url, params: {
        employee: {
          employee_number: "EMP503",
          name: "No Date",
          country_id: @us.id,
          department_id: @engineering.id,
          initial_salary: "50000",
          salary_effective_from: ""
        }
      }
    end
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /can't be blank/
    assert_nil Employee.find_by(employee_number: "EMP503")
  end

  test "add employee preserves entered form values upon validation failure" do
    post employees_url, params: {
      employee: {
        employee_number: "EMP504",
        name: "",
        country_id: @in.id,
        department_id: @product.id,
        initial_salary: "95000",
        salary_effective_from: "2026-03-01"
      }
    }

    assert_response :unprocessable_entity
    assert_select "input[name='employee[employee_number]'][value='EMP504']"
    assert_select "input[name='employee[initial_salary]'][value='95000']"
    assert_select "input[name='employee[salary_effective_from]'][value='2026-03-01']"
  end

  # =====================
  # Edit Employee Tests
  # =====================

  test "show page has Edit Employee button linking to edit form" do
    emp = Employee.create!(employee_number: "EMP510", name: "Ada Lovelace", country: @us, department: @engineering)
    get employee_url(emp)
    assert_response :success
    assert_select "a.btn-primary[href='#{edit_employee_path(emp)}']", text: "Edit Employee"
  end

  test "edit form renders existing employee values" do
    emp = Employee.create!(employee_number: "EMP511", name: "Katherine Johnson", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 80_000, effective_from: Date.new(2026, 1, 1))

    get edit_employee_url(emp)
    assert_response :success
    assert_select "h1.page-title", "Edit Employee"
    assert_select "input[name='employee[employee_number]'][value='EMP511']"
    assert_select "input[name='employee[name]'][value='Katherine Johnson']"
    assert_select "select[name='employee[country_id]'] option[selected]", text: "United States"
    assert_select "select[name='employee[department_id]'] option[selected]", text: "Engineering"
  end

  test "updating employee details without salary input does not create a Salary record" do
    emp = Employee.create!(employee_number: "EMP512", name: "Old Name", country: @us, department: @engineering)
    initial_sal = emp.salaries.create!(annual_salary: 80_000, effective_from: Date.new(2026, 1, 1))

    assert_no_difference "Salary.count" do
      patch employee_url(emp), params: {
        employee: {
          employee_number: "EMP512-NEW",
          name: "Updated Name",
          country_id: @in.id,
          department_id: @product.id,
          new_salary: "",
          salary_effective_from: ""
        }
      }
    end

    assert_redirected_to employee_path(emp)
    emp.reload
    assert_equal "EMP512-NEW", emp.employee_number
    assert_equal "Updated Name", emp.name
    assert_equal @in.id, emp.country_id
    assert_equal @product.id, emp.department_id
    assert_equal [ initial_sal ], emp.salaries.to_a
  end

  test "submitting a salary change creates a new record and preserves existing history" do
    emp = Employee.create!(employee_number: "EMP513", name: "Salary Raiser", country: @us, department: @engineering)
    old_sal = emp.salaries.create!(annual_salary: 70_000, effective_from: Date.new(2025, 1, 1))

    assert_difference "Salary.count", 1 do
      patch employee_url(emp), params: {
        employee: {
          employee_number: "EMP513",
          name: "Salary Raiser",
          country_id: @us.id,
          department_id: @engineering.id,
          new_salary: "85000",
          salary_effective_from: "2026-01-01"
        }
      }
    end

    assert_redirected_to employee_path(emp)
    emp.reload
    assert_equal 2, emp.salaries.count
    assert_includes emp.salaries, old_sal

    new_sal = emp.salaries.find_by!(effective_from: Date.new(2026, 1, 1))
    assert_equal 85_000.to_d, new_sal.annual_salary

    # Confirm history display on show page contains both records
    get employee_url(emp)
    assert_response :success
    assert_select "td.salary-amount", text: /\$85,000/
    assert_select "td.salary-amount", text: /\$70,000/
  end

  test "future-effective salaries do not replace the current salary prematurely" do
    emp = Employee.create!(employee_number: "EMP514", name: "Future Raiser", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.current - 6.months)

    # Schedule raise in 3 months
    patch employee_url(emp), params: {
      employee: {
        employee_number: "EMP514",
        name: "Future Raiser",
        country_id: @us.id,
        department_id: @engineering.id,
        new_salary: "90000",
        salary_effective_from: (Date.current + 3.months).to_s
      }
    }

    assert_redirected_to employee_path(emp)
    emp.reload

    # Current salary must remain 60,000
    assert_equal 60_000.to_d, emp.current_annual_salary

    get employee_url(emp)
    assert_response :success
    assert_select ".employee-current-salary", text: /\$60,000/
    assert_select ".employee-current-salary", text: /\$90,000/, count: 0
    # But salary history table includes the future row
    assert_select "td.salary-amount", text: /\$90,000/
  end

  test "duplicate effective dates on salary change are handled gracefully" do
    emp = Employee.create!(employee_number: "EMP515", name: "Dup Date Tester", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 50_000, effective_from: Date.new(2026, 1, 1))

    assert_no_difference "Salary.count" do
      patch employee_url(emp), params: {
        employee: {
          employee_number: "EMP515",
          name: "Dup Date Tester",
          country_id: @us.id,
          department_id: @engineering.id,
          new_salary: "60000",
          salary_effective_from: "2026-01-01"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /has already been taken/
    emp.reload
    assert_equal 50_000.to_d, emp.salaries.first.annual_salary
  end

  test "invalid employee IDs on edit and update return 404" do
    get edit_employee_url(-1)
    assert_response :not_found

    patch employee_url(-1), params: { employee: { name: "Ghost" } }
    assert_response :not_found
  end

  test "failed updates do not leave partially saved employee or salary changes" do
    emp = Employee.create!(employee_number: "EMP516", name: "Transactional Test", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 50_000, effective_from: Date.new(2026, 1, 1))

    # We try to change name to "Renamed Person" but pass an invalid salary amount (-100)
    assert_no_difference "Salary.count" do
      patch employee_url(emp), params: {
        employee: {
          employee_number: "EMP516",
          name: "Renamed Person",
          country_id: @us.id,
          department_id: @engineering.id,
          new_salary: "-100",
          salary_effective_from: "2026-06-01"
        }
      }
    end

    assert_response :unprocessable_entity
    emp.reload
    # Employee name must NOT have been updated
    assert_equal "Transactional Test", emp.name
  end
end
