require "test_helper"

class PeriodTest < ActiveSupport::TestCase
  test "valid period" do
    period = Period.new(year: 2026, month: 3)
    assert period.valid?
  end

  test "invalid without year" do
    period = Period.new(month: 3)
    assert_not period.valid?
    assert_includes period.errors[:year], "can't be blank"
  end

  test "invalid with year before 1900" do
    period = Period.new(year: 1800, month: 3)
    assert_not period.valid?
    assert_includes period.errors[:year], "must be greater than 1900"
  end

  test "invalid without month" do
    period = Period.new(year: 2026)
    assert_not period.valid?
    assert_includes period.errors[:month], "can't be blank"
  end

  test "invalid with month out of range" do
    [ 0, 13, -1 ].each do |invalid_month|
      period = Period.new(year: 2026, month: invalid_month)
      assert_not period.valid?, "Month #{invalid_month} should be invalid"
      assert_includes period.errors[:month], "must be in 1..12"
    end
  end

  test "enforces unique period per year and month" do
    Period.create!(year: 2026, month: 6)
    duplicate = Period.new(year: 2026, month: 6)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:month], "has already been taken"
  end

  test "allows same month in different years" do
    Period.create!(year: 2025, month: 6)
    next_year_period = Period.new(year: 2026, month: 6)
    assert next_year_period.valid?
  end
end
