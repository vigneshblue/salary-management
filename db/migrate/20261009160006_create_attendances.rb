class CreateAttendances < ActiveRecord::Migration[8.1]
  def change
    create_table :attendances do |t|
      t.references :employee, null: false, foreign_key: true, index: false
      t.references :period, null: false, foreign_key: true
      t.integer :working_days, null: false
      t.integer :present_days, null: false

      t.timestamps
    end

    add_index :attendances, [ :employee_id, :period_id ], unique: true
  end
end
