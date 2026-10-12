require "test_helper"

class AttendanceTest < ActiveSupport::TestCase
  setup do
    country = Country.create!(name: "India", code: "IN", currency: "INR")
    department = Department.create!(name: "Engineering")
    @employee = Employee.create!(employee_number: "EMP400", name: "Rahul", country: country, department: department, joining_date: Date.new(2026, 1, 1))
    @period = Period.create!(year: 2026, month: 4)
  end

  test "valid attendance" do
    attendance = Attendance.new(
      employee: @employee,
      period: @period,
      working_days: 22,
      present_days: 20
    )
    assert attendance.valid?
  end

  test "invalid without employee" do
    attendance = Attendance.new(period: @period, working_days: 22, present_days: 20)
    assert_not attendance.valid?
    assert_includes attendance.errors[:employee], "must exist"
  end

  test "invalid without period" do
    attendance = Attendance.new(employee: @employee, working_days: 22, present_days: 20)
    assert_not attendance.valid?
    assert_includes attendance.errors[:period], "must exist"
  end

  test "invalid without working_days" do
    attendance = Attendance.new(employee: @employee, period: @period, present_days: 20)
    assert_not attendance.valid?
    assert_includes attendance.errors[:working_days], "can't be blank"
  end

  test "invalid without present_days" do
    attendance = Attendance.new(employee: @employee, period: @period, working_days: 22)
    assert_not attendance.valid?
    assert_includes attendance.errors[:present_days], "can't be blank"
  end

  test "invalid with negative days" do
    attendance = Attendance.new(employee: @employee, period: @period, working_days: -1, present_days: -2)
    assert_not attendance.valid?
    assert_includes attendance.errors[:working_days], "must be greater than or equal to 0"
    assert_includes attendance.errors[:present_days], "must be greater than or equal to 0"
  end

  test "invalid when present_days exceed working_days" do
    attendance = Attendance.new(
      employee: @employee,
      period: @period,
      working_days: 20,
      present_days: 22
    )
    assert_not attendance.valid?
    assert_includes attendance.errors[:present_days], "cannot exceed working days"
  end

  test "enforces unique attendance per employee and period" do
    Attendance.create!(employee: @employee, period: @period, working_days: 22, present_days: 22)
    duplicate = Attendance.new(employee: @employee, period: @period, working_days: 20, present_days: 18)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:employee_id], "has already been taken"
  end
end
