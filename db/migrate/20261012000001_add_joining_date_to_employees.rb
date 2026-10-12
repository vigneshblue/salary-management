class AddJoiningDateToEmployees < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add column with a temporary default so existing rows satisfy NOT NULL.
    add_column :employees, :joining_date, :date, null: false, default: "2020-01-01"
    # Step 2: Remove the server-side default so the application must supply values explicitly.
    change_column_default :employees, :joining_date, from: "2020-01-01", to: nil
  end

  def down
    remove_column :employees, :joining_date
  end
end
