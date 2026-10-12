require "test_helper"

class CountryTest < ActiveSupport::TestCase
  test "valid country" do
    country = Country.new(name: "United States", code: "US", currency: "USD")
    assert country.valid?
  end

  test "invalid without name" do
    country = Country.new(code: "US", currency: "USD")
    assert_not country.valid?
    assert_includes country.errors[:name], "can't be blank"
  end

  test "invalid without code" do
    country = Country.new(name: "United States", currency: "USD")
    assert_not country.valid?
    assert_includes country.errors[:code], "can't be blank"
  end

  test "invalid without currency" do
    country = Country.new(name: "United States", code: "US")
    assert_not country.valid?
    assert_includes country.errors[:currency], "can't be blank"
  end

  test "enforces unique code case insensitively" do
    Country.create!(name: "United States", code: "US", currency: "USD")
    duplicate = Country.new(name: "USA", code: "us", currency: "USD")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"
  end

  test "restricts deletion when employees exist" do
    country = Country.create!(name: "United States", code: "US", currency: "USD")
    department = Department.create!(name: "Engineering")
    country.employees.create!(name: "John Doe", employee_number: "EMP001", department: department, joining_date: Date.new(2026, 1, 1))

    assert_no_difference "Country.count" do
      country.destroy
    end
    assert_includes country.errors[:base], "Cannot delete record because dependent employees exist"
  end
end
