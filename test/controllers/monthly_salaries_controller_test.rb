require "test_helper"

class MonthlySalariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @in = Country.create!(name: "India", code: "IN", currency: "INR")
    @engineering = Department.create!(name: "Engineering")
  end

  test "salary calculation page renders successfully" do
    get monthly_salaries_url
    assert_response :success
    assert_select "h1.page-title", "Monthly Salaries"
    assert_select "form.attendance-form"
    assert_select "input[type='submit'][value='Calculate Salaries']"
  end

  test "navigation sidebar includes link to Monthly Salaries" do
    get monthly_salaries_url
    assert_response :success
    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href='#{monthly_salaries_path}']", text: /Monthly Salaries/
    end
  end

  test "correct salary and payable amount are calculated and rounded" do
    emp = Employee.create!(employee_number: "EMP101", name: "Alice", country: @us, department: @engineering)
    # Annual salary: $65,000.00
    # Monthly base = 65000 / 12 = 5416.6666... -> rounded to 5416.67
    # Working days = 22, Present days = 20
    # Payable = (5416.67 * 20) / 22 = 4924.24545... -> rounded to 4924.25
    emp.salaries.create!(annual_salary: 65_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 3)
    Attendance.create!(employee: emp, period: period, working_days: 22, present_days: 20)

    assert_difference("MonthlySalary.count", 1) do
      post monthly_salaries_url, params: { year: 2026, month: 3 }
    end

    assert_redirected_to monthly_salaries_path(year: "2026", month: "3")
    follow_redirect!
    assert_select ".alert-success", text: /Successfully calculated monthly salaries for all 1 employees/

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("5416.67"), ms.monthly_salary
    assert_equal BigDecimal("4924.25"), ms.payable_amount
    assert_equal "Pending", ms.status
  end

  test "applicable salary is selected according to the first-day-of-month rule" do
    emp = Employee.create!(employee_number: "EMP102", name: "Bob", country: @us, department: @engineering)

    # 1. Salary effective earlier: $60,000
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2025, 1, 1))
    # 2. Salary effective on first day of month (March 1, 2026): $72,000 (should be chosen)
    emp.salaries.create!(annual_salary: 72_000, effective_from: Date.new(2026, 3, 1))
    # 3. Salary effective after first day of month (March 15, 2026): $96,000 (should NOT be chosen)
    emp.salaries.create!(annual_salary: 96_000, effective_from: Date.new(2026, 3, 15))

    period = Period.create!(year: 2026, month: 3)
    Attendance.create!(employee: emp, period: period, working_days: 20, present_days: 20)

    post monthly_salaries_url, params: { year: 2026, month: 3 }

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    # Monthly base should be 72,000 / 12 = 6000.00, NOT 96,000 / 12 = 8000.00
    assert_equal BigDecimal("6000.00"), ms.monthly_salary
    assert_equal BigDecimal("6000.00"), ms.payable_amount
  end

  test "missing attendance prevents partial creation" do
    emp1 = Employee.create!(employee_number: "EMP201", name: "User 1", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP202", name: "User 2", country: @us, department: @engineering)

    emp1.salaries.create!(annual_salary: 50_000, effective_from: Date.new(2026, 1, 1))
    emp2.salaries.create!(annual_salary: 50_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 4)
    # Only emp1 has attendance; emp2 is missing
    Attendance.create!(employee: emp1, period: period, working_days: 20, present_days: 20)

    assert_no_difference("MonthlySalary.count") do
      post monthly_salaries_url, params: { year: 2026, month: 4 }
    end

    assert_redirected_to monthly_salaries_path(year: "2026", month: "4")
    follow_redirect!
    assert_select ".alert-danger", text: /Attendance has not been generated for all employees/
    assert_select ".alert-danger", text: /No partial salaries created/
  end

  test "missing applicable salary prevents partial creation" do
    emp1 = Employee.create!(employee_number: "EMP301", name: "User 1", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP302", name: "User 2", country: @us, department: @engineering)

    # emp1 has valid salary; emp2 has no salary records on or before May 1, 2026
    emp1.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2026, 1, 1))
    emp2.salaries.create!(annual_salary: 70_000, effective_from: Date.new(2026, 5, 2)) # effective May 2 (after 1st)

    period = Period.create!(year: 2026, month: 5)
    Attendance.create!(employee: emp1, period: period, working_days: 20, present_days: 20)
    Attendance.create!(employee: emp2, period: period, working_days: 20, present_days: 20)

    assert_no_difference("MonthlySalary.count") do
      post monthly_salaries_url, params: { year: 2026, month: 5 }
    end

    assert_redirected_to monthly_salaries_path(year: "2026", month: "5")
    follow_redirect!
    assert_select ".alert-danger", text: /1 employee\(s\) do not have an applicable salary record on or before May 01, 2026/
    assert_select ".alert-danger", text: /No partial salaries created/
  end

  test "zero working days are handled safely" do
    emp = Employee.create!(employee_number: "EMP401", name: "User Zero", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 48_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 6)
    Attendance.create!(employee: emp, period: period, working_days: 0, present_days: 0)

    assert_difference("MonthlySalary.count", 1) do
      post monthly_salaries_url, params: { year: 2026, month: 6 }
    end

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("4000.00"), ms.monthly_salary
    assert_equal BigDecimal("0.00"), ms.payable_amount
  end

  test "repeated calculation preserves existing records and creates no duplicates" do
    emp = Employee.create!(employee_number: "EMP501", name: "User Rep", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 7)
    Attendance.create!(employee: emp, period: period, working_days: 20, present_days: 20)

    post monthly_salaries_url, params: { year: 2026, month: 7 }
    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("5000.00"), ms.payable_amount

    # Manually update to check if preserved
    ms.update!(payable_amount: BigDecimal("3333.33"))

    assert_no_difference("MonthlySalary.count") do
      post monthly_salaries_url, params: { year: 2026, month: 7 }
    end

    assert_redirected_to monthly_salaries_path(year: "2026", month: "7")
    follow_redirect!
    assert_select ".alert-success", text: /already been calculated.*preserved/

    ms.reload
    assert_equal BigDecimal("3333.33"), ms.payable_amount
  end

  test "newly created records have Pending status" do
    emp = Employee.create!(employee_number: "EMP601", name: "User Pend", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 72_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 8)
    Attendance.create!(employee: emp, period: period, working_days: 22, present_days: 22)

    post monthly_salaries_url, params: { year: 2026, month: 8 }
    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal "Pending", ms.status
  end

  test "currency totals are not combined across different currencies" do
    emp_us = Employee.create!(employee_number: "EMP701", name: "US Emp", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP702", name: "IN Emp", country: @in, department: @engineering)

    emp_us.salaries.create!(annual_salary: 120_000, effective_from: Date.new(2026, 1, 1))
    emp_in.salaries.create!(annual_salary: 1_200_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 9)
    Attendance.create!(employee: emp_us, period: period, working_days: 20, present_days: 20)
    Attendance.create!(employee: emp_in, period: period, working_days: 20, present_days: 20)

    post monthly_salaries_url, params: { year: 2026, month: 9 }
    follow_redirect!

    assert_response :success
    # Should report separate totals for USD and INR
    assert_select ".stat-card", text: /USD Total/
    assert_select ".stat-card", text: /\$10,000\.00/

    assert_select ".stat-card", text: /INR Total/
    assert_select ".stat-card", text: /₹100,000\.00/
  end

  # ==================================
  # Salary Processing Tests
  # ==================================

  test "processing changes Pending records to Paid" do
    emp = Employee.create!(employee_number: "EMP801", name: "Proc Test", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 10)
    Attendance.create!(employee: emp, period: period, working_days: 20, present_days: 20)

    # First calculate salaries (creates Pending record)
    post monthly_salaries_url, params: { year: 2026, month: 10 }
    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal "Pending", ms.status

    # Now process pending salaries
    post process_salaries_monthly_salaries_url, params: { year: 2026, month: 10 }
    assert_redirected_to monthly_salaries_path(year: "2026", month: "10")
    follow_redirect!
    assert_select ".alert-success", text: /Successfully processed 1 pending salaries/

    ms.reload
    assert_equal "Paid", ms.status
  end

  test "already-Paid records remain unchanged and are not counted as newly processed" do
    emp1 = Employee.create!(employee_number: "EMP802", name: "User Paid", country: @us, department: @engineering)
    emp2 = Employee.create!(employee_number: "EMP803", name: "User Pend", country: @us, department: @engineering)
    period = Period.create!(year: 2026, month: 11)

    MonthlySalary.create!(employee: emp1, period: period, monthly_salary: 5000, payable_amount: 5000, status: "Paid")
    MonthlySalary.create!(employee: emp2, period: period, monthly_salary: 4000, payable_amount: 4000, status: "Pending")

    post process_salaries_monthly_salaries_url, params: { year: 2026, month: 11 }
    assert_redirected_to monthly_salaries_path(year: "2026", month: "11")
    follow_redirect!
    assert_select ".alert-success", text: /Successfully processed 1 pending salaries/

    assert_equal "Paid", MonthlySalary.find_by(employee: emp1, period: period).status
    assert_equal "Paid", MonthlySalary.find_by(employee: emp2, period: period).status
  end

  test "salary amounts are unchanged during processing" do
    emp = Employee.create!(employee_number: "EMP804", name: "User Unchanged", country: @us, department: @engineering)
    period = Period.create!(year: 2026, month: 12)

    MonthlySalary.create!(
      employee: emp,
      period: period,
      monthly_salary: BigDecimal("5432.10"),
      payable_amount: BigDecimal("4321.09"),
      status: "Pending"
    )

    post process_salaries_monthly_salaries_url, params: { year: 2026, month: 12 }

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal "Paid", ms.status
    assert_equal BigDecimal("5432.10"), ms.monthly_salary
    assert_equal BigDecimal("4321.09"), ms.payable_amount
  end

  test "repeated processing is safe and reports zero newly processed records when appropriate" do
    emp = Employee.create!(employee_number: "EMP805", name: "User Repeat", country: @us, department: @engineering)
    period = Period.create!(year: 2026, month: 1)
    MonthlySalary.create!(employee: emp, period: period, monthly_salary: 5000, payable_amount: 5000, status: "Paid")

    post process_salaries_monthly_salaries_url, params: { year: 2026, month: 1 }
    assert_redirected_to monthly_salaries_path(year: "2026", month: "1")
    follow_redirect!
    assert_select ".alert-success", text: /already processed and marked as Paid \(0 pending records newly processed\)/
  end

  test "only records for the selected period are processed" do
    emp = Employee.create!(employee_number: "EMP806", name: "User MultiPeriod", country: @us, department: @engineering)
    p_target = Period.create!(year: 2025, month: 5)
    p_other = Period.create!(year: 2025, month: 6)

    ms_target = MonthlySalary.create!(employee: emp, period: p_target, monthly_salary: 5000, payable_amount: 5000, status: "Pending")
    ms_other = MonthlySalary.create!(employee: emp, period: p_other, monthly_salary: 5000, payable_amount: 5000, status: "Pending")

    post process_salaries_monthly_salaries_url, params: { year: 2025, month: 5 }

    assert_equal "Paid", ms_target.reload.status
    assert_equal "Pending", ms_other.reload.status
  end

  test "an empty period or period with no pending records is handled gracefully" do
    Period.create!(year: 2025, month: 7)

    post process_salaries_monthly_salaries_url, params: { year: 2025, month: 7 }
    assert_redirected_to monthly_salaries_path(year: "2025", month: "7")
    follow_redirect!
    assert_select ".alert-danger", text: /No pending salary records found to process for July 2025/
  end

  test "currency totals are reported separately upon processing" do
    emp_us = Employee.create!(employee_number: "EMP807", name: "US Emp", country: @us, department: @engineering)
    emp_in = Employee.create!(employee_number: "EMP808", name: "IN Emp", country: @in, department: @engineering)
    period = Period.create!(year: 2025, month: 8)

    MonthlySalary.create!(employee: emp_us, period: period, monthly_salary: 5000, payable_amount: 5000, status: "Pending")
    MonthlySalary.create!(employee: emp_in, period: period, monthly_salary: 100_000, payable_amount: 100_000, status: "Pending")

    post process_salaries_monthly_salaries_url, params: { year: 2025, month: 8 }
    assert_redirected_to monthly_salaries_path(year: "2025", month: "8")
    follow_redirect!

    assert_select ".alert-success", text: /\$5,000\.00/
    assert_select ".alert-success", text: /₹100,000\.00/
  end

  test "a database failure rolls back the operation" do
    emp = Employee.create!(employee_number: "EMP809", name: "Fail Test", country: @us, department: @engineering)
    period = Period.create!(year: 2025, month: 9)
    MonthlySalary.create!(employee: emp, period: period, monthly_salary: 5000, payable_amount: 5000, status: "Pending")

    # Temporarily override call on SalaryProcessor to simulate database failure
    original_call = SalaryProcessor.method(:call)
    SalaryProcessor.define_singleton_method(:call) do |**_args|
      SalaryProcessor::Result.new(
        success?: false,
        error_message: "Database error during salary processing: simulated failure"
      )
    end

    begin
      post process_salaries_monthly_salaries_url, params: { year: 2025, month: 9 }
      assert_redirected_to monthly_salaries_path(year: "2025", month: "9")
      follow_redirect!
      assert_select ".alert-danger", text: /Database error during salary processing/
    ensure
      SalaryProcessor.define_singleton_method(:call, original_call)
    end

    assert_equal "Pending", MonthlySalary.find_by(employee: emp, period: period).status
  end

  test "invalid period input is handled appropriately" do
    post process_salaries_monthly_salaries_url, params: { year: "invalid", month: "99" }
    assert_redirected_to monthly_salaries_path(year: "invalid", month: "99")
    follow_redirect!
    assert_select ".alert-danger", text: /Year must be an integer/
  end

  # ==================================
  # Period Synchronization Tests
  # ==================================

  test "visiting with year and month params shows the selected period in the Period Summary header" do
    get monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "h2", text: /Period Summary: June 2025/
    assert_select "p", text: /Selected Period:.*June 2025/
  end

  test "visiting with year and month params reflects them in the form selects" do
    get monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "select[name='year'] option[selected]", text: "2025"
    assert_select "select[name='month'] option[selected]", text: "June"
  end

  test "cross-navigation link to Attendance carries the selected year and month" do
    get monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "a[href*='year=2025'][href*='month=6']", text: /Attendance/
  end

  test "sidebar Monthly Salaries link preserves year and month when params are present" do
    get monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href*='year=2025'][href*='month=6']", text: /Monthly Salaries/
    end
  end

  test "sidebar Attendance link preserves year and month when params are present" do
    get monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href*='year=2025'][href*='month=6']", text: /Attendance/
    end
  end

  test "calculate salaries action redirects with the selected year and month in the URL" do
    emp = Employee.create!(employee_number: "EMP_MS_SYNC1", name: "Sync Calc", country: @us, department: @engineering)
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2025, 1, 1))
    period = Period.create!(year: 2025, month: 6)
    Attendance.create!(employee: emp, period: period, working_days: 20, present_days: 20)

    post monthly_salaries_url, params: { year: 2025, month: 6 }
    assert_redirected_to monthly_salaries_path(year: "2025", month: "6")

    follow_redirect!
    assert_select "h2", text: /Period Summary: June 2025/
  end

  test "process salaries action redirects with the selected year and month in the URL" do
    emp = Employee.create!(employee_number: "EMP_MS_SYNC2", name: "Sync Proc", country: @us, department: @engineering)
    period = Period.create!(year: 2025, month: 4)
    MonthlySalary.create!(employee: emp, period: period, monthly_salary: 5000, payable_amount: 5000, status: "Pending")

    post process_salaries_monthly_salaries_url, params: { year: 2025, month: 4 }
    assert_redirected_to monthly_salaries_path(year: "2025", month: "4")

    follow_redirect!
    assert_select "h2", text: /Period Summary: April 2025/
  end

  test "missing year and month params default to the current month on the index page" do
    get monthly_salaries_url
    assert_response :success

    current = Date.current
    assert_select "h2", text: /Period Summary: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end

  test "invalid year param shows an alert and falls back to the current month" do
    get monthly_salaries_url, params: { year: 1800, month: 6 }
    assert_response :success

    current = Date.current
    assert_select ".alert-danger", text: /Year must be an integer greater than 1900/
    assert_select "h2", text: /Period Summary: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end

  test "invalid month param shows an alert and falls back to the current month" do
    get monthly_salaries_url, params: { year: 2025, month: 99 }
    assert_response :success

    current = Date.current
    assert_select ".alert-danger", text: /Month must be between 1 and 12/
    assert_select "h2", text: /Period Summary: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end
end
