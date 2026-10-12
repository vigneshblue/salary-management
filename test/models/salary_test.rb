require "test_helper"

class SalaryTest < ActiveSupport::TestCase
  setup do
    country = Country.create!(name: "United Kingdom", code: "GB", currency: "GBP")
    department = Department.create!(name: "Product")
    @employee = Employee.create!(employee_number: "EMP300", name: "Jane Doe", country: country, department: department, joining_date: Date.new(2026, 1, 1))
  end

  test "valid salary" do
    salary = Salary.new(
      employee: @employee,
      annual_salary: 75_000.50,
      effective_from: Date.new(2026, 1, 1)
    )
    assert salary.valid?
  end

  test "invalid without employee" do
    salary = Salary.new(annual_salary: 75_000, effective_from: Date.new(2026, 1, 1))
    assert_not salary.valid?
    assert_includes salary.errors[:employee], "must exist"
  end

  test "invalid without annual_salary" do
    salary = Salary.new(employee: @employee, effective_from: Date.new(2026, 1, 1))
    assert_not salary.valid?
    assert_includes salary.errors[:annual_salary], "can't be blank"
  end

  test "invalid with negative annual_salary" do
    salary = Salary.new(employee: @employee, annual_salary: -100, effective_from: Date.new(2026, 1, 1))
    assert_not salary.valid?
    assert_includes salary.errors[:annual_salary], "must be greater than or equal to 0"
  end

  test "invalid without effective_from" do
    salary = Salary.new(employee: @employee, annual_salary: 50_000)
    assert_not salary.valid?
    assert_includes salary.errors[:effective_from], "can't be blank"
  end

  test "enforces unique effective_from per employee" do
    effective_date = Date.new(2026, 1, 1)
    Salary.create!(employee: @employee, annual_salary: 60_000, effective_from: effective_date)
    duplicate = Salary.new(employee: @employee, annual_salary: 70_000, effective_from: effective_date)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:effective_from], "has already been taken"
  end

  test "allows same effective_from for different employees" do
    country = Country.create!(name: "France", code: "FR", currency: "EUR")
    department = Department.create!(name: "Design")
    other_employee = Employee.create!(employee_number: "EMP301", name: "Pierre", country: country, department: department, joining_date: Date.new(2026, 1, 1))

    effective_date = Date.new(2026, 1, 1)
    Salary.create!(employee: @employee, annual_salary: 60_000, effective_from: effective_date)
    other_salary = Salary.new(employee: other_employee, annual_salary: 65_000, effective_from: effective_date)
    assert other_salary.valid?
  end
end
