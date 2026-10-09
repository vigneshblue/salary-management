class Period < ApplicationRecord
  has_many :attendances, dependent: :destroy
  has_many :monthly_salaries, dependent: :destroy

  validates :year, presence: true, numericality: { only_integer: true, greater_than: 1900 }
  validates :month, presence: true, numericality: { only_integer: true, in: 1..12 }, uniqueness: { scope: :year }
end
