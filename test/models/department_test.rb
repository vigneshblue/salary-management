require "test_helper"

class DepartmentTest < ActiveSupport::TestCase
  test "valid department" do
    department = Department.new(name: "Human Resources")
    assert department.valid?
  end

  test "invalid without name" do
    department = Department.new(name: nil)
    assert_not department.valid?
    assert_includes department.errors[:name], "can't be blank"
  end

  test "enforces unique name" do
    Department.create!(name: "Finance")
    duplicate = Department.new(name: "Finance")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "restricts deletion when employees exist" do
    country = Country.create!(name: "India", code: "IN", currency: "INR")
    department = Department.create!(name: "Operations")
    department.employees.create!(name: "Alice", employee_number: "EMP002", country: country)

    assert_no_difference "Department.count" do
      department.destroy
    end
    assert_includes department.errors[:base], "Cannot delete record because dependent employees exist"
  end
end
