require "test_helper"

class MonthlySalaryTest < ActiveSupport::TestCase
  setup do
    country = Country.create!(name: "United States", code: "US", currency: "USD")
    department = Department.create!(name: "Marketing")
    @employee = Employee.create!(employee_number: "EMP500", name: "Sarah Connor", country: country, department: department)
    @period = Period.create!(year: 2026, month: 5)
  end

  test "valid monthly salary with pending status" do
    monthly_salary = MonthlySalary.new(
      employee: @employee,
      period: @period,
      monthly_salary: 5000.00,
      payable_amount: 4500.00,
      status: "Pending"
    )
    assert monthly_salary.valid?
  end

  test "valid monthly salary with paid status" do
    monthly_salary = MonthlySalary.new(
      employee: @employee,
      period: @period,
      monthly_salary: 5000.00,
      payable_amount: 5000.00,
      status: "Paid"
    )
    assert monthly_salary.valid?
  end

  test "invalid without employee" do
    monthly_salary = MonthlySalary.new(period: @period, monthly_salary: 5000, payable_amount: 5000, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:employee], "must exist"
  end

  test "invalid without period" do
    monthly_salary = MonthlySalary.new(employee: @employee, monthly_salary: 5000, payable_amount: 5000, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:period], "must exist"
  end

  test "invalid without monthly_salary" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, payable_amount: 5000, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:monthly_salary], "can't be blank"
  end

  test "invalid with negative monthly_salary" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: -10, payable_amount: 5000, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:monthly_salary], "must be greater than or equal to 0"
  end

  test "invalid without payable_amount" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: 5000, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:payable_amount], "can't be blank"
  end

  test "invalid with negative payable_amount" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: 5000, payable_amount: -5, status: "Pending")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:payable_amount], "must be greater than or equal to 0"
  end

  test "invalid without status" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: 5000, payable_amount: 5000, status: nil)
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:status], "can't be blank"
  end

  test "invalid with unsupported status" do
    monthly_salary = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: 5000, payable_amount: 5000, status: "Cancelled")
    assert_not monthly_salary.valid?
    assert_includes monthly_salary.errors[:status], "is not included in the list"
  end

  test "enforces unique monthly salary per employee and period" do
    MonthlySalary.create!(employee: @employee, period: @period, monthly_salary: 5000, payable_amount: 5000, status: "Pending")
    duplicate = MonthlySalary.new(employee: @employee, period: @period, monthly_salary: 5000, payable_amount: 5000, status: "Paid")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:employee_id], "has already been taken"
  end
end
