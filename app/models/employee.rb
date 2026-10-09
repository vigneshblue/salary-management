class Employee < ApplicationRecord
  belongs_to :country
  belongs_to :department

  has_many :salaries, dependent: :destroy
  has_many :attendances, dependent: :destroy
  has_many :monthly_salaries, dependent: :destroy

  validates :employee_number, presence: true, uniqueness: true
  validates :name, presence: true
end
