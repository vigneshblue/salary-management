class Salary < ApplicationRecord
  belongs_to :employee

  validates :annual_salary, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :effective_from, presence: true, uniqueness: { scope: :employee_id }
end
