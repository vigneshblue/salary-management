class CreateMonthlySalaries < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_salaries do |t|
      t.references :employee, null: false, foreign_key: true, index: false
      t.references :period, null: false, foreign_key: true
      t.decimal :monthly_salary, precision: 15, scale: 2, null: false
      t.decimal :payable_amount, precision: 15, scale: 2, null: false
      t.string :status, null: false

      t.timestamps
    end

    add_index :monthly_salaries, [ :employee_id, :period_id ], unique: true
  end
end
