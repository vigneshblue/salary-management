require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @in = Country.create!(name: "India", code: "IN", currency: "INR")
    @uk = Country.create!(name: "United Kingdom", code: "GB", currency: "GBP")

    @engineering = Department.create!(name: "Engineering")
    @sales = Department.create!(name: "Sales")
  end

  test "dashboard renders successfully on root path and shows organization metrics" do
    Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP002", name: "Bob", country: @in, department: @sales)

    get root_url
    assert_response :success
    assert_select "h1.page-title", "Salary Insights Dashboard"
    assert_select ".stat-card .stat-value", text: "2" # Total employees
    assert_select "td", text: "United States"
    assert_select "td", text: "India"
    assert_select "td", text: "Engineering"
    assert_select "td", text: "Sales"
  end

  test "only Dashboard navigation item is active on root page" do
    get root_url
    assert_response :success
    assert_select "aside.sidebar" do
      # Only one active nav item
      assert_select "a.nav-item.active", count: 1
      assert_select "a.nav-item.active", text: /Dashboard/
      # Other nav items exist but are not active
      assert_select "a.nav-item[href='#{employees_path}']:not(.active)", text: /Employees/
      assert_select "a.nav-item[href='#{attendances_path}']:not(.active)", text: /Attendance/
      assert_select "a.nav-item[href='#{monthly_salaries_path}']:not(.active)", text: /Monthly Salaries/
      # No Insights link exists
      assert_select "a.nav-item", text: /Insights/, count: 0
    end
  end

  test "headcount charts render SVG elements" do
    Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    Employee.create!(employee_number: "EMP002", name: "Bob", country: @in, department: @sales)

    get root_url
    assert_response :success

    # Country headcount chart
    assert_select "svg.chart-headcount-country"
    assert_select "svg.chart-headcount-country title", text: /United States/
    assert_select "svg.chart-headcount-country title", text: /India/

    # Department headcount chart
    assert_select "svg.chart-headcount-dept"
    assert_select "svg.chart-headcount-dept title", text: /Engineering/
    assert_select "svg.chart-headcount-dept title", text: /Sales/
  end

  test "salary distribution chart renders with selected reporting currency labels" do
    emp_us = Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP002", name: "Bob", country: @in, department: @sales)

    emp_us.salaries.create!(annual_salary: 100_000, effective_from: Date.current - 1.month)
    emp_in.salaries.create!(annual_salary: 1_500_000, effective_from: Date.current - 1.month)

    # In default INR:
    get root_url
    assert_response :success

    assert_select "svg.chart-salary-country"
    assert_select "svg.chart-salary-country text", text: "INR", count: 2

    # In USD:
    get root_url, params: { currency: "USD" }
    assert_response :success
    assert_select "svg.chart-salary-country text", text: "USD", count: 2
  end

  test "payroll trend chart renders with period data" do
    emp = Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    p1 = Period.create!(year: 2026, month: 1)
    MonthlySalary.create!(employee: emp, period: period = p1, monthly_salary: 5000, payable_amount: 5000, status: "Paid")

    get root_url
    assert_response :success

    assert_select "svg.chart-payroll-trend"
    assert_select "svg.chart-payroll-trend title", text: /January 2026/
  end

  test "salary metrics select latest salary effective on or before reporting date" do
    emp = Employee.create!(employee_number: "EMP003", name: "Charlie", country: @us, department: @engineering)

    # Historical salary: $50,000
    emp.salaries.create!(annual_salary: 50_000, effective_from: Date.current - 2.years)
    # Current salary: $80,000 (effective 1 month ago)
    emp.salaries.create!(annual_salary: 80_000, effective_from: Date.current - 1.month)
    # Future raise: $120,000 (effective next month)
    emp.salaries.create!(annual_salary: 120_000, effective_from: Date.current + 1.month)

    # In USD:
    get dashboard_url, params: { currency: "USD" }
    assert_response :success

    # Should report $80,000 as average and min/max in USD, NOT $120,000 or $50,000
    assert_select "td.country-avg-salary", text: /\$80,000\.00/
    assert_select "td.country-avg-salary", text: /\$120,000\.00/, count: 0
  end

  test "department breakdown reports converted values in selected currency" do
    emp_us1 = Employee.create!(employee_number: "EMP004", name: "US 1", country: @us, department: @engineering)
    emp_us2 = Employee.create!(employee_number: "EMP005", name: "US 2", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP006", name: "IN 1", country: @in, department: @engineering)

    emp_us1.salaries.create!(annual_salary: 100_000, effective_from: Date.current - 1.month)
    emp_us2.salaries.create!(annual_salary: 120_000, effective_from: Date.current - 1.month)
    emp_in.salaries.create!(annual_salary: 1_500_000, effective_from: Date.current - 1.month)

    get dashboard_url
    assert_response :success

    # In Country breakdown (default currency INR):
    # US average: ($100k + $120k)/2 = $110k -> 110k * 83 = ₹9,130,000.00
    # IN average: ₹1,500,000.00
    assert_select "#country-salary-united-states .country-avg-salary", text: /₹9,130,000\.00/
    assert_select "#country-salary-india .country-avg-salary", text: /₹1,500,000\.00/

    # In Department breakdown with default currency INR:
    # Engineering combines US 1 ($100k -> ₹8.3M), US 2 ($120k -> ₹9.96M), IN 1 (₹1.5M)
    # Min: 1,500,000.00
    # Max: 9,960,000.00
    # Avg: (8.3M + 9.96M + 1.5M)/3 = 19.76M / 3 = 6,586,666.67
    assert_select "td.dept-salary-name", text: "Engineering", count: 1
    assert_select "td.dept-min-salary", text: /₹1,500,000\.00/
    assert_select "td.dept-max-salary", text: /₹9,960,000\.00/
    assert_select "td.dept-avg-salary", text: /₹6,586,666\.67/
  end

  test "monthly payroll insights converts Paid and Pending totals into selected currency" do
    emp1 = Employee.create!(employee_number: "EMP007", name: "User Paid", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP008", name: "User Pending", country: @us, department: @engineering)

    period = Period.create!(year: 2026, month: 3)
    MonthlySalary.create!(employee: emp1, period: period, monthly_salary: 5000, payable_amount: 4500, status: "Paid")
    MonthlySalary.create!(employee: emp2, period: period, monthly_salary: 6000, payable_amount: 5500, status: "Pending")

    # Default currency is INR: $4,500 * 83 = ₹373,500.00; $5,500 * 83 = ₹456,500.00
    get dashboard_url, params: { year: 2026, month: 3 }
    assert_response :success

    assert_select ".stat-card", text: /Paid Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select ".paid-total-converted", text: /₹373,500\.00 \(INR\)/
    end

    assert_select ".stat-card", text: /Pending Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select ".pending-total-converted", text: /₹456,500\.00 \(INR\)/
    end
  end

  test "recent monthly payroll trends displays historical cycles" do
    emp = Employee.create!(employee_number: "EMP009", name: "User Trend", country: @us, department: @engineering)
    p1 = Period.create!(year: 2026, month: 1)
    p2 = Period.create!(year: 2026, month: 2)

    MonthlySalary.create!(employee: emp, period: p1, monthly_salary: 5000, payable_amount: 5000, status: "Paid")
    MonthlySalary.create!(employee: emp, period: p2, monthly_salary: 5000, payable_amount: 5000, status: "Pending")

    get dashboard_url
    assert_response :success

    assert_select "td", text: "January 2026"
    assert_select "td", text: "February 2026"
  end

  test "gracefully handles empty database" do
    assert_equal 0, Employee.count
    assert_equal 0, Period.count

    get root_url
    assert_response :success
    assert_select "h1.page-title", "Salary Insights Dashboard"
    assert_select ".empty-state", text: /No country data available/
    assert_select ".empty-state", text: /No department data available/
    assert_select ".empty-state", text: /No salary records available/
    assert_select ".empty-state", text: /No historical payroll periods found/
  end

  # =====================
  # Currency Selector Tests
  # =====================

  test "default reporting currency is INR" do
    get root_url
    assert_response :success
    assert_select "select[name='currency']" do
      assert_select "option[selected][value='INR']"
    end
    assert_select "h2", text: /Annual Salary Insights by Department \(INR\)/
    assert_select "h2", text: /Monthly Payroll Insights \(INR\)/
  end

  test "selecting another currency updates department and monthly payroll sections" do
    emp = Employee.create!(employee_number: "EMP020", name: "Currency Switcher", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 83_000, effective_from: Date.current - 1.month)
    period = Period.create!(year: 2026, month: 4)
    MonthlySalary.create!(employee: emp, period: period, monthly_salary: 8300, payable_amount: 8300, status: "Paid")

    # In USD:
    # 83,000 USD converted to USD = $83,000.00
    # Monthly paid: 8,300 USD converted to USD = $8,300.00
    get root_url, params: { currency: "USD", year: 2026, month: 4 }
    assert_response :success

    assert_select "select[name='currency'] option[selected][value='USD']"
    assert_select "h2", text: /Annual Salary Insights by Department \(USD\)/
    assert_select "h2", text: /Monthly Payroll Insights \(USD\)/

    assert_select "td.dept-min-salary", text: /\$83,000\.00/
    assert_select "td.dept-avg-salary", text: /\$83,000\.00/
    assert_select "td.dept-max-salary", text: /\$83,000\.00/

    assert_select ".paid-total-converted", text: /\$8,300\.00 \(USD\)/
  end

  test "department min, avg, and max use converted values before calculating aggregates" do
    # US employee: 83,000 USD (at 83 INR/USD => 6,889,000 INR)
    # IN employee: 3,444,500 INR
    emp1 = Employee.create!(employee_number: "EMP021", name: "US Dev", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP022", name: "IN Dev", country: @in, department: @engineering)

    emp1.salaries.create!(annual_salary: 83_000, effective_from: Date.current - 1.month)
    emp2.salaries.create!(annual_salary: 3_444_500, effective_from: Date.current - 1.month)

    # When viewing in USD:
    # emp1 in USD = 83,000.00
    # emp2 in USD = 3,444,500 / 83 = 41,500.00
    # Min = 41,500.00, Max = 83,000.00, Avg = (83,000 + 41,500)/2 = 62,250.00
    get root_url, params: { currency: "USD" }
    assert_response :success

    assert_select "td.dept-min-salary", text: /\$41,500\.00/
    assert_select "td.dept-max-salary", text: /\$83,000\.00/
    assert_select "td.dept-avg-salary", text: /\$62,250\.00/
  end

  test "monthly paid and pending totals use converted values without altering employee counts" do
    emp1 = Employee.create!(employee_number: "EMP023", name: "US Paid", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP024", name: "IN Pending", country: @in, department: @engineering)

    period = Period.create!(year: 2026, month: 5)
    # 100 USD paid (100 * 83 = 8300 INR)
    MonthlySalary.create!(employee: emp1, period: period, monthly_salary: 100, payable_amount: 100, status: "Paid")
    # 8300 INR pending
    MonthlySalary.create!(employee: emp2, period: period, monthly_salary: 8300, payable_amount: 8300, status: "Pending")

    # In USD:
    # Paid: 100 USD = $100.00
    # Pending: 8300 INR / 83 = $100.00
    get root_url, params: { currency: "USD", year: 2026, month: 5 }
    assert_response :success

    assert_select ".stat-card", text: /Paid Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select ".paid-total-converted", text: /\$100\.00 \(USD\)/
    end

    assert_select ".stat-card", text: /Pending Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select ".pending-total-converted", text: /\$100\.00 \(USD\)/
    end
  end

  test "invalid currency input falls back safely to INR" do
    get root_url, params: { currency: "INVALID_XYZ" }
    assert_response :success

    assert_select "select[name='currency'] option[selected][value='INR']"
    assert_select "h2", text: /Annual Salary Insights by Department \(INR\)/
    assert_select "h2", text: /Monthly Payroll Insights \(INR\)/
  end

  test "selected currency is retained when changing reporting period" do
    period = Period.create!(year: 2026, month: 6)

    get root_url, params: { currency: "GBP", year: 2026, month: 6 }
    assert_response :success

    # Ensure period form includes hidden currency field with GBP
    assert_select "form.attendance-form input[type='hidden'][name='currency'][value='GBP']"
    assert_select "select[name='currency'] option[selected][value='GBP']"
  end

  test "annual salary distribution by country uses converted values in selected currency and excludes future-effective salaries" do
    emp_us1 = Employee.create!(employee_number: "EMP030", name: "US Worker 1", country: @us, department: @engineering)
    emp_us2 = Employee.create!(employee_number: "EMP031", name: "US Worker 2", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP032", name: "IN Worker", country: @in, department: @sales)

    # US Worker 1: 50,000 USD (past) -> 80,000 USD (current) -> 150,000 USD (future)
    emp_us1.salaries.create!(annual_salary: 50_000, effective_from: Date.current - 1.year)
    emp_us1.salaries.create!(annual_salary: 80_000, effective_from: Date.current - 1.month)
    emp_us1.salaries.create!(annual_salary: 150_000, effective_from: Date.current + 1.month)

    # US Worker 2: 120,000 USD (current)
    emp_us2.salaries.create!(annual_salary: 120_000, effective_from: Date.current - 1.month)

    # IN Worker: 1,660,000 INR (current)
    emp_in.salaries.create!(annual_salary: 1_660_000, effective_from: Date.current - 1.month)

    # Viewing in USD:
    # US country min: $80,000, max: $120,000, avg: ($80,000 + $120,000)/2 = $100,000 (future $150,000 excluded)
    # IN country: 1,660,000 INR / 83 = $20,000
    get root_url, params: { currency: "USD" }
    assert_response :success

    assert_select "h2", text: /Annual Salary Distribution by Country \(USD\)/

    # Check US row
    assert_select "#country-salary-united-states" do
      assert_select ".country-min-salary", text: /\$80,000\.00/
      assert_select ".country-max-salary", text: /\$120,000\.00/
      assert_select ".country-avg-salary", text: /\$100,000\.00/
    end

    # Check IN row
    assert_select "#country-salary-india" do
      assert_select ".country-min-salary", text: /\$20,000\.00/
      assert_select ".country-max-salary", text: /\$20,000\.00/
      assert_select ".country-avg-salary", text: /\$20,000\.00/
    end

    # Viewing in INR (default):
    # US Worker 1 ($80k) -> 6,640,000 INR
    # US Worker 2 ($120k) -> 9,960,000 INR
    # US country min: ₹6,640,000.00, max: ₹9,960,000.00, avg: ₹8,300,000.00
    get root_url, params: { currency: "INR" }
    assert_response :success

    assert_select "h2", text: /Annual Salary Distribution by Country \(INR\)/
    assert_select "#country-salary-united-states" do
      assert_select ".country-min-salary", text: /₹6,640,000\.00/
      assert_select ".country-max-salary", text: /₹9,960,000\.00/
      assert_select ".country-avg-salary", text: /₹8,300,000\.00/
    end
    assert_select "#country-salary-india" do
      assert_select ".country-min-salary", text: /₹1,660,000\.00/
      assert_select ".country-max-salary", text: /₹1,660,000\.00/
      assert_select ".country-avg-salary", text: /₹1,660,000\.00/
    end
  end
end
