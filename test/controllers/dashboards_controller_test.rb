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

  test "salary distribution chart renders with currency labels" do
    emp_us = Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP002", name: "Bob", country: @in, department: @sales)

    emp_us.salaries.create!(annual_salary: 100_000, effective_from: Date.current - 1.month)
    emp_in.salaries.create!(annual_salary: 1_500_000, effective_from: Date.current - 1.month)

    get root_url
    assert_response :success

    assert_select "svg.chart-salary-country"
    assert_select "svg.chart-salary-country text", text: "USD"
    assert_select "svg.chart-salary-country text", text: "INR"
  end

  test "payroll trend chart renders with period data" do
    emp = Employee.create!(employee_number: "EMP001", name: "Alice", country: @us, department: @engineering)
    p1 = Period.create!(year: 2026, month: 1)
    MonthlySalary.create!(employee: emp, period: p1, monthly_salary: 5000, payable_amount: 5000, status: "Paid")

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

    get dashboard_url
    assert_response :success

    # Should report $80,000 as average and min/max, NOT $120,000 or $50,000
    assert_select "td.col-salary", text: /\$80,000\.00/
    assert_select "td.col-salary", text: /\$120,000\.00/, count: 0
  end

  test "currency separation: does not merge amounts across currencies" do
    emp_us1 = Employee.create!(employee_number: "EMP004", name: "US 1", country: @us, department: @engineering)
    emp_us2 = Employee.create!(employee_number: "EMP005", name: "US 2", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP006", name: "IN 1", country: @in, department: @engineering)

    emp_us1.salaries.create!(annual_salary: 100_000, effective_from: Date.current - 1.month)
    emp_us2.salaries.create!(annual_salary: 120_000, effective_from: Date.current - 1.month)
    emp_in.salaries.create!(annual_salary: 1_500_000, effective_from: Date.current - 1.month)

    get dashboard_url
    assert_response :success

    # In Country breakdown:
    # US average: $110,000
    assert_select "td.col-salary", text: /\$110,000\.00/
    # IN average: ₹1,500,000
    assert_select "td.col-salary", text: /₹1,500,000\.00/

    # In Department breakdown:
    # Engineering appears separately for USD and INR
    assert_select "td.dept-salary-name", text: "Engineering", count: 2
  end

  test "monthly payroll insights separates Paid and Pending counts and totals" do
    emp1 = Employee.create!(employee_number: "EMP007", name: "User Paid", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP008", name: "User Pending", country: @us, department: @engineering)

    period = Period.create!(year: 2026, month: 3)
    MonthlySalary.create!(employee: emp1, period: period, monthly_salary: 5000, payable_amount: 4500, status: "Paid")
    MonthlySalary.create!(employee: emp2, period: period, monthly_salary: 6000, payable_amount: 5500, status: "Pending")

    get dashboard_url, params: { year: 2026, month: 3 }
    assert_response :success

    # Paid card
    assert_select ".stat-card", text: /Paid Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select "div", text: /\$4,500\.00 \(USD\)/
    end

    # Pending card
    assert_select ".stat-card", text: /Pending Employee Count/ do
      assert_select ".stat-value", text: /1/
      assert_select "div", text: /\$5,500\.00 \(USD\)/
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
end
