require "test_helper"

class EmployeeTest < ActiveSupport::TestCase
  setup do
    @country = Country.create!(name: "Germany", code: "DE", currency: "EUR")
    @department = Department.create!(name: "Technology")
  end

  test "valid employee" do
    employee = Employee.new(
      employee_number: "EMP100",
      name: "Max Mustermann",
      country: @country,
      department: @department
    )
    assert employee.valid?
  end

  test "invalid without employee_number" do
    employee = Employee.new(name: "Max", country: @country, department: @department)
    assert_not employee.valid?
    assert_includes employee.errors[:employee_number], "can't be blank"
  end

  test "invalid without name" do
    employee = Employee.new(employee_number: "EMP101", country: @country, department: @department)
    assert_not employee.valid?
    assert_includes employee.errors[:name], "can't be blank"
  end

  test "invalid without country" do
    employee = Employee.new(employee_number: "EMP102", name: "Max", department: @department)
    assert_not employee.valid?
    assert_includes employee.errors[:country], "must exist"
  end

  test "invalid without department" do
    employee = Employee.new(employee_number: "EMP103", name: "Max", country: @country)
    assert_not employee.valid?
    assert_includes employee.errors[:department], "must exist"
  end

  test "enforces unique employee_number" do
    Employee.create!(employee_number: "EMP100", name: "First", country: @country, department: @department)
    duplicate = Employee.new(employee_number: "EMP100", name: "Second", country: @country, department: @department)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:employee_number], "has already been taken"
  end

  test "cascades deletion to salaries, attendances, and monthly_salaries" do
    employee = Employee.create!(employee_number: "EMP200", name: "Cascade Test", country: @country, department: @department)
    period = Period.create!(year: 2026, month: 1)
    employee.salaries.create!(annual_salary: 100_000, effective_from: Date.new(2026, 1, 1))
    employee.attendances.create!(period: period, working_days: 20, present_days: 20)
    employee.monthly_salaries.create!(period: period, monthly_salary: 8333.33, payable_amount: 8333.33, status: "Pending")

    assert_difference "Employee.count", -1 do
      assert_difference "Salary.count", -1 do
        assert_difference "Attendance.count", -1 do
          assert_difference "MonthlySalary.count", -1 do
            employee.destroy
          end
        end
      end
    end
  end
end
