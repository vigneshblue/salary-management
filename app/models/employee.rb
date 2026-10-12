class Employee < ApplicationRecord
  belongs_to :country
  belongs_to :department

  has_many :salaries, dependent: :destroy
  has_many :attendances, dependent: :destroy
  has_many :monthly_salaries, dependent: :destroy

  validates :employee_number, presence: true, uniqueness: true
  validates :name, presence: true
  # joining_date is required. It governs attendance eligibility and payable salary:
  # - Attendance eligible working days start from the later of month-start and joining_date.
  # - Employees who join after a payroll month ends receive no attendance or salary for that month.
  validates :joining_date, presence: true

  def current_salary(as_of = Date.current)
    if salaries.loaded?
      salaries.select { |s| s.effective_from.present? && s.effective_from <= as_of }
              .max_by(&:effective_from)
    else
      salaries.where("effective_from <= ?", as_of).order(effective_from: :desc).first
    end
  end

  def current_annual_salary(as_of = Date.current)
    current_salary(as_of)&.annual_salary
  end
end
