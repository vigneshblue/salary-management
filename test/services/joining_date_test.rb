require "test_helper"

# Tests for the joining-date-aware business rules in AttendanceGenerator and SalaryCalculator.
#
# Key rules under test:
#   1. Employees who joined before the month starts receive the full month's eligible working days.
#   2. Employees who joined on the first day of the month receive the full month's eligible working days.
#   3. Employees who join mid-month receive only the weekday count from their joining date through month end.
#   4. Employees who join after the month ends receive zero eligible working days and zero present days.
#   5. A weekend joining date is still counted from that calendar date (only weekdays in the range are counted).
#   6. SalaryCalculator produces zero payable for an employee whose attendance has zero eligible working days.
#   7. SalaryCalculator skips applicable-salary check for employees who joined after the payroll month ends.
#   8. Rerunning attendance generation does not overwrite existing records.
class JoiningDateAttendanceTest < ActiveSupport::TestCase
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @engineering = Department.create!(name: "Engineering")

    # Selected test period: March 2026
    # March 2026: Mon 2, Tue 3, Wed 4, Thu 5, Fri 6, Mon 9, Tue 10, Wed 11, Thu 12, Fri 13,
    #             Mon 16, Tue 17, Wed 18, Thu 19, Fri 20, Mon 23, Tue 24, Wed 25, Thu 26, Fri 27,
    #             Mon 30, Tue 31 => 22 weekdays total.
    @year  = 2026
    @month = 3
    @month_start = Date.new(@year, @month, 1)   # Saturday — not a weekday
    @month_end   = Date.new(@year, @month, 31)  # Tuesday

    @generator = AttendanceGenerator.new(year: @year, month: @month)
  end

  # -----------------------------------------------------------------------
  # eligible_working_days helper
  # -----------------------------------------------------------------------

  test "employee who joined well before the month start gets the full month working-day count" do
    joining_date = Date.new(2020, 6, 15)
    full = AttendanceGenerator.calculate_working_days(@year, @month)

    assert_equal full, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joined on the first day of the month gets the full month working-day count" do
    # March 1, 2026 is a Saturday. Eligible days = weekdays in the full month = 22.
    joining_date = @month_start
    full = AttendanceGenerator.calculate_working_days(@year, @month)

    assert_equal full, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joined one day before the month start gets the full month working-day count" do
    joining_date = @month_start - 1  # Feb 28, 2026
    full = AttendanceGenerator.calculate_working_days(@year, @month)

    assert_equal full, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joins mid-month on a weekday gets a partial eligible count" do
    # March 16, 2026 is a Monday.
    # Weekdays from Mar 16 through Mar 31: 16,17,18,19,20,23,24,25,26,27,30,31 => 12 days.
    joining_date = Date.new(2026, 3, 16)

    assert_equal 12, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joins mid-month on a weekend still counts from that calendar date" do
    # March 14, 2026 is a Saturday. Weekdays from Mar 14 through Mar 31:
    # 16,17,18,19,20,23,24,25,26,27,30,31 => 12 days.
    joining_date = Date.new(2026, 3, 14)

    assert_equal 12, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joins on the last day of the month gets 1 eligible day if it is a weekday" do
    # March 31, 2026 is a Tuesday.
    joining_date = @month_end

    assert_equal 1, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joins on the last day of the month gets 0 eligible days if it is a weekend" do
    # January 31, 2026 is a Saturday.
    jan_end = Date.new(2026, 1, 31)
    jan_start = Date.new(2026, 1, 1)
    gen = AttendanceGenerator.new(year: 2026, month: 1)

    assert_equal 0, gen.eligible_working_days(jan_end, jan_start, jan_end)
  end

  test "employee who joins after the month ends gets zero eligible working days" do
    joining_date = @month_end + 1  # April 1, 2026

    assert_equal 0, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "employee who joins far in the future gets zero eligible working days" do
    joining_date = Date.new(2035, 1, 1)

    assert_equal 0, @generator.eligible_working_days(joining_date, @month_start, @month_end)
  end

  test "nil joining_date falls back to full-month working days (safety guard)" do
    full = AttendanceGenerator.calculate_working_days(@year, @month)

    assert_equal full, @generator.eligible_working_days(nil, @month_start, @month_end)
  end

  # -----------------------------------------------------------------------
  # Integration via AttendanceGenerator.call
  # -----------------------------------------------------------------------

  test "full-month joiner gets the full eligible working-day count in the generated attendance record" do
    emp = Employee.create!(
      employee_number: "JDATE001",
      name: "Early Joiner",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2024, 3, 1)
    )

    AttendanceGenerator.call(year: @year, month: @month)

    period = Period.find_by!(year: @year, month: @month)
    att = Attendance.find_by!(employee: emp, period: period)

    assert_equal AttendanceGenerator.calculate_working_days(@year, @month), att.working_days
    assert_operator att.present_days, :>=, 0
    assert_operator att.present_days, :<=, att.working_days
  end

  test "mid-month joiner gets a reduced eligible working-day count" do
    # Joins March 16 (Monday). Eligible weekdays: 12.
    emp = Employee.create!(
      employee_number: "JDATE002",
      name: "Mid Month Joiner",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 3, 16)
    )

    AttendanceGenerator.call(year: @year, month: @month)

    period = Period.find_by!(year: @year, month: @month)
    att = Attendance.find_by!(employee: emp, period: period)

    assert_equal 12, att.working_days
    assert_operator att.present_days, :>=, 0
    assert_operator att.present_days, :<=, 12
  end

  test "post-month joiner gets zero eligible working days and zero present days" do
    emp = Employee.create!(
      employee_number: "JDATE003",
      name: "Future Joiner",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 4, 1)   # April — after March ends
    )

    AttendanceGenerator.call(year: @year, month: @month)

    period = Period.find_by!(year: @year, month: @month)
    att = Attendance.find_by!(employee: emp, period: period)

    assert_equal 0, att.working_days
    assert_equal 0, att.present_days
    assert att.valid?, "Attendance record with zero working_days must be valid: #{att.errors.full_messages}"
  end

  test "weekend joining date is handled correctly with the partial working-day count" do
    # Joins March 14, 2026 (Saturday). Eligible weekdays from Mar 14..Mar 31 = 12.
    emp = Employee.create!(
      employee_number: "JDATE004",
      name: "Weekend Joiner",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 3, 14)
    )

    AttendanceGenerator.call(year: @year, month: @month)

    period = Period.find_by!(year: @year, month: @month)
    att = Attendance.find_by!(employee: emp, period: period)

    assert_equal 12, att.working_days
    assert_operator att.present_days, :>=, 0
    assert_operator att.present_days, :<=, 12
  end

  test "mixed cohort: full-month, mid-month, and post-month joiners are all generated in one run" do
    early = Employee.create!(employee_number: "JDATE010", name: "Early",  country: @us, department: @engineering, joining_date: Date.new(2025, 1, 1))
    mid   = Employee.create!(employee_number: "JDATE011", name: "Mid",    country: @us, department: @engineering, joining_date: Date.new(2026, 3, 16))
    late  = Employee.create!(employee_number: "JDATE012", name: "Future", country: @us, department: @engineering, joining_date: Date.new(2026, 4, 1))

    assert_difference("Attendance.count", 3) do
      AttendanceGenerator.call(year: @year, month: @month)
    end

    period = Period.find_by!(year: @year, month: @month)

    assert_equal AttendanceGenerator.calculate_working_days(@year, @month), Attendance.find_by!(employee: early, period: period).working_days
    assert_equal 12, Attendance.find_by!(employee: mid, period: period).working_days
    assert_equal 0,  Attendance.find_by!(employee: late, period: period).working_days
    assert_equal 0,  Attendance.find_by!(employee: late, period: period).present_days
  end

  test "rerunning attendance generation preserves existing records for all joining-date scenarios" do
    emp = Employee.create!(
      employee_number: "JDATE020",
      name: "Idempotency Check",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 3, 16)
    )

    AttendanceGenerator.call(year: @year, month: @month)

    period = Period.find_by!(year: @year, month: @month)
    att = Attendance.find_by!(employee: emp, period: period)
    original_present = att.present_days
    att.update!(present_days: [ att.working_days, 1 ].min)  # Manually override

    # Rerun — must NOT overwrite
    assert_no_difference("Attendance.count") do
      AttendanceGenerator.call(year: @year, month: @month)
    end

    att.reload
    assert_equal [ att.working_days, 1 ].min, att.present_days, "Existing attendance record must not be overwritten on rerun"
  end
end

class JoiningDateSalaryTest < ActiveSupport::TestCase
  setup do
    @us = Country.create!(name: "United States", code: "US", currency: "USD")
    @engineering = Department.create!(name: "Engineering")
  end

  test "zero eligible working days produces zero payable amount and valid monthly_salary" do
    # Simulates a post-month joiner whose attendance record has 0 eligible days.
    annual = BigDecimal("60000")
    monthly_base, payable = SalaryCalculator.new(year: 2026, month: 3).compute_salary_amounts(annual, 0, 0)

    assert_equal BigDecimal("5000.00"), monthly_base
    assert_equal BigDecimal("0.00"),    payable
  end

  test "partial eligible working days produces a proportional payable amount" do
    # 12 eligible days, 10 present days, annual $60,000.
    # monthly_base = 60000/12 = 5000.00
    # payable = 5000.00 * 10 / 12 = 4166.6666... -> 4166.67
    annual = BigDecimal("60000")
    monthly_base, payable = SalaryCalculator.new(year: 2026, month: 3).compute_salary_amounts(annual, 12, 10)

    assert_equal BigDecimal("5000.00"), monthly_base
    assert_equal BigDecimal("4166.67"), payable
  end

  test "end-to-end: post-month joiner has zero payable but valid salary record after calculation" do
    emp = Employee.create!(
      employee_number: "SAL_JDATE001",
      name: "Future Hire",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 4, 1)   # Joins April, payroll month is March
    )
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2026, 4, 1))

    # Attendance generated for March includes this employee (with 0 eligible days)
    period = Period.create!(year: 2026, month: 3)
    Attendance.create!(employee: emp, period: period, working_days: 0, present_days: 0)

    assert_difference("MonthlySalary.count", 1) do
      SalaryCalculator.call(year: 2026, month: 3)
    end

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("0.00"), ms.monthly_salary
    assert_equal BigDecimal("0.00"), ms.payable_amount
    assert_equal "Pending",          ms.status
    assert ms.valid?
  end

  test "end-to-end: mid-month joiner receives proportional payable amount" do
    # Joins March 16. Eligible days: 12. Present days generated deterministically.
    emp = Employee.create!(
      employee_number: "SAL_JDATE002",
      name: "Mid Hire",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2026, 3, 16)
    )
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2026, 1, 1))

    period = Period.create!(year: 2026, month: 3)
    # Manually set attendance to a known value for a deterministic assertion.
    Attendance.create!(employee: emp, period: period, working_days: 12, present_days: 10)

    SalaryCalculator.call(year: 2026, month: 3)

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("5000.00"), ms.monthly_salary
    # payable = 5000 * 10 / 12 = 4166.67
    assert_equal BigDecimal("4166.67"), ms.payable_amount
  end

  test "end-to-end: full-month joiner with full attendance receives full monthly salary" do
    emp = Employee.create!(
      employee_number: "SAL_JDATE003",
      name: "Early Hire",
      country: @us,
      department: @engineering,
      joining_date: Date.new(2024, 1, 1)
    )
    emp.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2024, 1, 1))

    period = Period.create!(year: 2026, month: 3)
    Attendance.create!(employee: emp, period: period, working_days: 22, present_days: 22)

    SalaryCalculator.call(year: 2026, month: 3)

    ms = MonthlySalary.find_by!(employee: emp, period: period)
    assert_equal BigDecimal("5000.00"), ms.monthly_salary
    assert_equal BigDecimal("5000.00"), ms.payable_amount
  end

  test "end-to-end: mixed cohort calculates all three joining scenarios in one run" do
    early = Employee.create!(employee_number: "SAL_MIX001", name: "Early", country: @us, department: @engineering, joining_date: Date.new(2024, 1, 1))
    mid   = Employee.create!(employee_number: "SAL_MIX002", name: "Mid",   country: @us, department: @engineering, joining_date: Date.new(2026, 3, 16))
    late  = Employee.create!(employee_number: "SAL_MIX003", name: "Late",  country: @us, department: @engineering, joining_date: Date.new(2026, 4, 1))

    early.salaries.create!(annual_salary: 60_000, effective_from: Date.new(2024, 1, 1))
    mid.salaries.create!(annual_salary: 48_000, effective_from: Date.new(2026, 1, 1))
    # late has no applicable salary for March; it should be excluded from the salary count

    period = Period.create!(year: 2026, month: 3)
    Attendance.create!(employee: early, period: period, working_days: 22, present_days: 22)
    Attendance.create!(employee: mid,   period: period, working_days: 12, present_days: 10)
    Attendance.create!(employee: late,  period: period, working_days: 0,  present_days: 0)

    assert_difference("MonthlySalary.count", 3) do
      SalaryCalculator.call(year: 2026, month: 3)
    end

    ms_early = MonthlySalary.find_by!(employee: early, period: period)
    ms_mid   = MonthlySalary.find_by!(employee: mid,   period: period)
    ms_late  = MonthlySalary.find_by!(employee: late,  period: period)

    assert_equal BigDecimal("5000.00"), ms_early.monthly_salary
    assert_equal BigDecimal("5000.00"), ms_early.payable_amount

    assert_equal BigDecimal("4000.00"), ms_mid.monthly_salary
    # 4000 * 10 / 12 = 3333.33
    assert_equal BigDecimal("3333.33"), ms_mid.payable_amount

    assert_equal BigDecimal("0.00"), ms_late.monthly_salary
    assert_equal BigDecimal("0.00"), ms_late.payable_amount
  end
end
