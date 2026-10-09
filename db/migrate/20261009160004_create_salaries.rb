class CreateSalaries < ActiveRecord::Migration[8.1]
  def change
    create_table :salaries do |t|
      t.references :employee, null: false, foreign_key: true, index: false
      t.decimal :annual_salary, precision: 15, scale: 2, null: false
      t.date :effective_from, null: false

      t.timestamps
    end

    add_index :salaries, [ :employee_id, :effective_from ], unique: true
  end
end
