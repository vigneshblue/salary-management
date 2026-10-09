class Employee < ApplicationRecord
  belongs_to :country
  belongs_to :department

  has_many :salaries, dependent: :destroy
  has_many :attendances, dependent: :destroy
  has_many :monthly_salaries, dependent: :destroy

  validates :employee_number, presence: true, uniqueness: true
  validates :name, presence: true

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
