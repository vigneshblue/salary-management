require "test_helper"

class AttendancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @engineering = Department.create!(name: "Engineering")
  end

  test "attendance page renders successfully" do
    get attendances_url
    assert_response :success
    assert_select "h1.page-title", "Attendance Management"
    assert_select "form.attendance-form"
    assert_select "select[name='year']"
    assert_select "select[name='month']"
    assert_select "input[type='submit'][value='Generate Attendance']"
  end

  test "navigation sidebar includes link to Attendance" do
    get attendances_url
    assert_response :success
    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href='#{attendances_path}']", text: /Attendance/
    end
  end

  test "invalid year/month inputs are rejected gracefully" do
    post attendances_url, params: { year: 1850, month: 5 }
    assert_redirected_to attendances_path(year: "1850", month: "5")
    follow_redirect!
    assert_select ".alert-danger", text: /Year must be an integer greater than 1900/

    post attendances_url, params: { year: 2026, month: 14 }
    assert_redirected_to attendances_path(year: "2026", month: "14")
    follow_redirect!
    assert_select ".alert-danger", text: /Month must be between 1 and 12/

    post attendances_url, params: { year: "", month: "" }
    assert_redirected_to attendances_path(year: "", month: "")
    follow_redirect!
    assert_select ".alert-danger", text: /Please provide both year and month/
  end

  test "period is created or reused correctly upon generation" do
    Employee.create!(employee_number: "EMP01", name: "Alice", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))

    assert_difference("Period.count", 1) do
      post attendances_url, params: { year: 2026, month: 7 }
    end

    period = Period.find_by(year: 2026, month: 7)
    assert_not_nil period

    # Generating again for the same period should reuse the existing Period
    assert_no_difference("Period.count") do
      post attendances_url, params: { year: 2026, month: 7 }
    end
  end

  test "attendance is generated for all employees" do
    5.times do |i|
      Employee.create!(
        employee_number: "EMP#{i + 10}",
        name: "Worker #{i + 1}",
        country: @us,
        department: @engineering,
        joining_date: Date.new(2026, 1, 1)
      )
    end

    assert_difference("Attendance.count", 5) do
      post attendances_url, params: { year: 2026, month: 3 }
    end

    assert_redirected_to attendances_path(year: "2026", month: "3")
    follow_redirect!
    assert_select ".alert-success", text: /Successfully generated attendance for all 5 employees/

    period = Period.find_by!(year: 2026, month: 3)
    assert_equal 5, period.attendances.count
  end

  test "working-day calculation excludes weekends" do
    # March 2026: 31 days total.
    # Saturdays: 7, 14, 21, 28 (4)
    # Sundays: 1, 8, 15, 22, 29 (5)
    # Total weekend days = 9. Total working days = 31 - 9 = 22.
    working_days = AttendanceGenerator.calculate_working_days(2026, 3)
    assert_equal 22, working_days

    # February 2026: 28 days total.
    # Feb 1 is Sunday.
    # Saturdays: 7, 14, 21, 28 (4)
    # Sundays: 1, 8, 15, 22 (4)
    # Total weekend days = 8. Total working days = 20.
    feb_working_days = AttendanceGenerator.calculate_working_days(2026, 2)
    assert_equal 20, feb_working_days
  end

  test "present days are within the range 0..working_days" do
    emp = Employee.create!(employee_number: "EMP99", name: "Zara", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))

    post attendances_url, params: { year: 2026, month: 4 }
    period = Period.find_by!(year: 2026, month: 4)
    attendance = Attendance.find_by!(employee: emp, period: period)

    working_days = AttendanceGenerator.calculate_working_days(2026, 4)
    assert_equal working_days, attendance.working_days
    assert_operator attendance.present_days, :>=, 0
    assert_operator attendance.present_days, :<=, attendance.working_days
    assert attendance.valid?
  end

  test "running generation twice does not create duplicates or overwrite existing records" do
    emp1 = Employee.create!(employee_number: "EMP101", name: "User 1", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))
    emp2 = Employee.create!(employee_number: "EMP102", name: "User 2", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))

    post attendances_url, params: { year: 2026, month: 5 }
    period = Period.find_by!(year: 2026, month: 5)
    assert_equal 2, period.attendances.count

    initial_records = period.attendances.order(:employee_id).pluck(:employee_id, :working_days, :present_days)

    # Modify one record manually to verify it is NOT overwritten
    att1 = period.attendances.find_by(employee: emp1)
    att1.update!(present_days: 12)

    # Rerun generation
    assert_no_difference("Attendance.count") do
      post attendances_url, params: { year: 2026, month: 5 }
    end

    assert_redirected_to attendances_path(year: "2026", month: "5")
    follow_redirect!
    assert_select ".alert-success", text: /All 2 existing records were preserved \(0 new records generated\)/

    # Verify existing modified record was preserved
    att1.reload
    assert_equal 12, att1.present_days

    # Verify second record remains unchanged
    att2 = period.attendances.find_by(employee: emp2)
    assert_equal initial_records.last[2], att2.present_days
  end

  test "partially existing attendance generates only missing employee records" do
    emp1 = Employee.create!(employee_number: "EMP201", name: "User 1", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))
    period = Period.create!(year: 2026, month: 8)
    Attendance.create!(employee: emp1, period: period, working_days: 21, present_days: 19)

    emp2 = Employee.create!(employee_number: "EMP202", name: "User 2", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))

    assert_difference("Attendance.count", 1) do
      post attendances_url, params: { year: 2026, month: 8 }
    end

    follow_redirect!
    assert_select ".alert-success", text: /Generated 1 new attendance records.*Preserved 1 existing attendance records/
    assert_equal 2, period.attendances.count
  end

  test "an empty employee database is handled gracefully" do
    assert_equal 0, Employee.count

    assert_no_difference("Attendance.count") do
      post attendances_url, params: { year: 2026, month: 10 }
    end

    assert_redirected_to attendances_path(year: "2026", month: "10")
    follow_redirect!
    assert_select ".alert-success", text: /No employees found in the system to generate attendance for/
  end

  # ==================================
  # Period Synchronization Tests
  # ==================================

  test "visiting with year and month params shows the selected period in the status header" do
    get attendances_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "h2", text: /Selected Period Status: June 2025/
    assert_select "p", text: /Selected Period:.*June 2025/
  end

  test "visiting with year and month params reflects them in the Generate form selects" do
    get attendances_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "select[name='year'] option[selected]", text: "2025"
    assert_select "select[name='month'] option[selected]", text: "June"
  end

  test "cross-navigation link to Monthly Salaries carries the selected year and month" do
    get attendances_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "a[href*='year=2025'][href*='month=6']", text: /Monthly Salaries/
  end

  test "sidebar Attendance link preserves year and month when params are present" do
    get attendances_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href*='year=2025'][href*='month=6']", text: /Attendance/
    end
  end

  test "sidebar Monthly Salaries link preserves year and month when params are present" do
    get attendances_url, params: { year: 2025, month: 6 }
    assert_response :success

    assert_select "aside.sidebar" do
      assert_select "a.nav-item[href*='year=2025'][href*='month=6']", text: /Monthly Salaries/
    end
  end

  test "attendance generation redirects with the selected year and month in the URL" do
    Employee.create!(employee_number: "EMP_SYNC1", name: "Sync Test", country: @us, department: @engineering, joining_date: Date.new(2026, 1, 1))

    post attendances_url, params: { year: 2025, month: 6 }
    assert_redirected_to attendances_path(year: "2025", month: "6")

    follow_redirect!
    assert_select "h2", text: /Selected Period Status: June 2025/
  end

  test "missing year and month params default to the current month on the index page" do
    get attendances_url
    assert_response :success

    current = Date.current
    assert_select "h2", text: /Selected Period Status: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end

  test "invalid year param shows an alert and falls back to the current month" do
    get attendances_url, params: { year: 1800, month: 6 }
    assert_response :success

    current = Date.current
    assert_select ".alert-danger", text: /Year must be an integer greater than 1900/
    assert_select "h2", text: /Selected Period Status: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end

  test "invalid month param shows an alert and falls back to the current month" do
    get attendances_url, params: { year: 2025, month: 99 }
    assert_response :success

    current = Date.current
    assert_select ".alert-danger", text: /Month must be between 1 and 12/
    assert_select "h2", text: /Selected Period Status: #{Date::MONTHNAMES[current.month]} #{current.year}/
  end

  # ==================================
  # Pagination and Filtering Tests
  # ==================================

  test "paginates attendance records with 25 records per page" do
    p = Period.create!(year: 2026, month: 1)
    30.times do |i|
      emp = Employee.create!(
        employee_number: format("ATTPAG%04d", i + 1),
        name: "Worker #{i + 1}",
        country: @us,
        department: @engineering,
        joining_date: Date.new(2025, 1, 1)
      )
      Attendance.create!(employee: emp, period: p, working_days: 22, present_days: 20)
    end

    get attendances_url, params: { year: 2026, month: 1, page: 1 }
    assert_response :success
    # 25 records in the page table (plus 1 period in recorded periods table)
    assert_select "#attendances_frame tbody tr", count: 25
    assert_select "#attendances_frame .pagination-info", text: /Showing 1 to 25 of 30 records/
    assert_select "#attendances_frame a.pagination-next"

    get attendances_url, params: { year: 2026, month: 1, page: 2 }
    assert_response :success
    assert_select "#attendances_frame tbody tr", count: 5
    assert_select "#attendances_frame .pagination-info", text: /Showing 26 to 30 of 30 records/
    assert_select "#attendances_frame a.pagination-prev"
  end

  test "filters attendance records by employee name and employee number" do
    p = Period.create!(year: 2026, month: 2)
    emp1 = Employee.create!(employee_number: "SRCH001", name: "Ada Lovelace", country: @us, department: @engineering, joining_date: Date.new(2025, 1, 1))
    emp2 = Employee.create!(employee_number: "SRCH002", name: "Alan Turing", country: @us, department: @engineering, joining_date: Date.new(2025, 1, 1))
    Attendance.create!(employee: emp1, period: p, working_days: 20, present_days: 20)
    Attendance.create!(employee: emp2, period: p, working_days: 20, present_days: 18)

    get attendances_url, params: { year: 2026, month: 2, q: "Lovelace" }
    assert_response :success
    assert_select "#attendances_frame tbody tr", count: 1
    assert_select "#attendances_frame td.employee-number", "SRCH001"

    get attendances_url, params: { year: 2026, month: 2, q: "SRCH002" }
    assert_response :success
    assert_select "#attendances_frame tbody tr", count: 1
    assert_select "#attendances_frame td.employee-number", "SRCH002"
  end

  test "filters attendance records by country, department, and status" do
    in_country = Country.create!(name: "India", code: "IN", currency: "INR")
    sales_dept = Department.create!(name: "Sales")

    p = Period.create!(year: 2026, month: 3)
    emp_us = Employee.create!(employee_number: "FILT001", name: "US Perfect", country: @us, department: @engineering, joining_date: Date.new(2025, 1, 1))
    emp_in = Employee.create!(employee_number: "FILT002", name: "IN Partial", country: in_country, department: sales_dept, joining_date: Date.new(2025, 1, 1))
    Attendance.create!(employee: emp_us, period: p, working_days: 22, present_days: 22)
    Attendance.create!(employee: emp_in, period: p, working_days: 22, present_days: 18)

    get attendances_url, params: { year: 2026, month: 3, country_id: @us.id }
    assert_response :success
    assert_select "#attendances_frame tbody tr", count: 1
    assert_select "#attendances_frame td.employee-number", "FILT001"

    get attendances_url, params: { year: 2026, month: 3, status: "partial" }
    assert_response :success
    assert_select "#attendances_frame tbody tr", count: 1
    assert_select "#attendances_frame td.employee-number", "FILT002"
  end

  test "displays zero absent days for post-month joiner with 0 working days" do
    p = Period.create!(year: 2026, month: 4)
    emp = Employee.create!(
      employee_number: "LATE001",
      name: "Late Hire",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 5, 1)
    )
    Attendance.create!(employee: emp, period: p, working_days: 0, present_days: 0)

    get attendances_url, params: { year: 2026, month: 4 }
    assert_response :success
    assert_select "#attendances_frame tr##{dom_id(emp.attendances.first)}" do
      assert_select "td.attendance-working-days", "0"
      assert_select "td.attendance-present-days", "0"
      assert_select "td.attendance-absent-days", "0"
      assert_select "span.badge", text: /Joined Post-Period/
    end
  end

  test "distinguishes between period not generated and no filter matches" do
    # 1. Period not generated
    get attendances_url, params: { year: 2028, month: 1 }
    assert_response :success
    assert_select "#attendances_frame td.empty-state", text: /No attendance records have been generated/

    # 2. Period exists, but filter has no matches
    p = Period.create!(year: 2026, month: 5)
    emp = Employee.create!(employee_number: "EX001", name: "Exists", country: @us, department: @engineering, joining_date: Date.new(2025, 1, 1))
    Attendance.create!(employee: emp, period: p, working_days: 20, present_days: 20)

    get attendances_url, params: { year: 2026, month: 5, q: "NonexistentName" }
    assert_response :success
    assert_select "#attendances_frame td.empty-state", text: /No attendance records match your search or filter/
  end
end
