class MonthlySalary < ApplicationRecord
  STATUS_PENDING = "Pending"
  STATUS_PAID = "Paid"
  STATUSES = [ STATUS_PENDING, STATUS_PAID ].freeze

  belongs_to :employee
  belongs_to :period

  validates :monthly_salary, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :payable_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :employee_id, uniqueness: { scope: :period_id }
end
