class Attendance < ApplicationRecord
  belongs_to :employee
  belongs_to :period

  validates :working_days, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :present_days, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :employee_id, uniqueness: { scope: :period_id }
  validate :present_days_cannot_exceed_working_days

  private

  def present_days_cannot_exceed_working_days
    return if working_days.blank? || present_days.blank?

    if present_days > working_days
      errors.add(:present_days, "cannot exceed working days")
    end
  end
end
