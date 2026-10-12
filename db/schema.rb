# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_12_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "attendances", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "period_id", null: false
    t.integer "working_days", null: false
    t.integer "present_days", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "period_id"], name: "index_attendances_on_employee_id_and_period_id", unique: true
    t.index ["period_id"], name: "index_attendances_on_period_id"
  end

  create_table "countries", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.string "currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_countries_on_code", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_departments_on_name", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.string "employee_number", null: false
    t.string "name", null: false
    t.bigint "country_id", null: false
    t.bigint "department_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "joining_date", null: false
    t.index ["country_id"], name: "index_employees_on_country_id"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["employee_number"], name: "index_employees_on_employee_number", unique: true
  end

  create_table "monthly_salaries", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "period_id", null: false
    t.decimal "monthly_salary", precision: 15, scale: 2, null: false
    t.decimal "payable_amount", precision: 15, scale: 2, null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "period_id"], name: "index_monthly_salaries_on_employee_id_and_period_id", unique: true
    t.index ["period_id"], name: "index_monthly_salaries_on_period_id"
  end

  create_table "periods", force: :cascade do |t|
    t.integer "year", null: false
    t.integer "month", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year", "month"], name: "index_periods_on_year_and_month", unique: true
  end

  create_table "salaries", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.decimal "annual_salary", precision: 15, scale: 2, null: false
    t.date "effective_from", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "effective_from"], name: "index_salaries_on_employee_id_and_effective_from", unique: true
  end

  add_foreign_key "attendances", "employees"
  add_foreign_key "attendances", "periods"
  add_foreign_key "employees", "countries"
  add_foreign_key "employees", "departments"
  add_foreign_key "monthly_salaries", "employees"
  add_foreign_key "monthly_salaries", "periods"
  add_foreign_key "salaries", "employees"
end
