class Country < ApplicationRecord
  has_many :employees, dependent: :restrict_with_error

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :currency, presence: true
end
