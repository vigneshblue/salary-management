class SalaryCalculator
  Result = Struct.new(
    :success?,
    :period,
    :total_employees,
    :calculated_count,
    :preserved_count,
    :currency_totals,
    :error_message,
    keyword_init: true
  )

  BATCH_SIZE = 1_000

  def self.call(year:, month:)
    new(year: year, month: month).call
  end

  def initialize(year:, month:)
    @year = year
    @month = month
  end

  def call
    validation_error = validate_inputs
    return Result.new(success?: false, error_message: validation_error) if validation_error

    period = Period.find_by(year: @year_int, month: @month_int)
    unless period
      period_label = "#{Date::MONTHNAMES[@month_int]} #{@year_int}"
      return Result.new(success?: false, error_message: "Period #{period_label} does not exist. Please generate attendance first.")
    end

    total_employees = Employee.count
    if total_employees.zero?
      return Result.new(
        success?: true,
        period: period,
        total_employees: 0,
        calculated_count: 0,
        preserved_count: 0,
        currency_totals: {}
      )
    end

    # First day of the selected month — used for the applicable salary rule.
    as_of_date  = Date.new(@year_int, @month_int, 1)
    month_end   = as_of_date.end_of_month

    # 1. Check attendance for all employees
    # All employees in the system must have an Attendance record for this period.
    attendances_by_employee_id = period.attendances
                                       .pluck(:employee_id, :working_days, :present_days)
                                       .to_h { |id, wd, pd| [ id, [ wd, pd ] ] }

    missing_attendance_count = total_employees - attendances_by_employee_id.size
    if missing_attendance_count.positive?
      period_label = "#{Date::MONTHNAMES[@month_int]} #{@year_int}"
      return Result.new(
        success?: false,
        error_message: "Cannot calculate salaries: Attendance has not been generated for all employees in #{period_label} (#{missing_attendance_count} missing). No partial salaries created."
      )
    end

    # 2. Check applicable salary records for all employees.
    # For each employee, select the latest salary with effective_from <= as_of_date.
    # Employees who joined after the month ends have no applicable salary (and no attendance).
    # However, to guard against legacy data, we also check joining dates independently.
    latest_salaries_query = Salary.where("effective_from <= ?", as_of_date)
                                  .select("DISTINCT ON (employee_id) employee_id, annual_salary, effective_from")
                                  .order("employee_id, effective_from DESC")

    salaries_by_employee_id = latest_salaries_query.to_h { |s| [ s.employee_id, s.annual_salary ] }

    # Fetch joining dates for all employees in one query.
    joining_dates_by_id = Employee.pluck(:id, :joining_date).to_h

    # Exclude employees who joined after this payroll month from the salary check.
    # They will receive a zero-payable record (their attendance will have 0 eligible days).
    # We only count employees who should have an applicable salary.
    employees_needing_salary = joining_dates_by_id.count { |_id, jd| jd.nil? || jd <= month_end }
    missing_salary_count = employees_needing_salary - salaries_by_employee_id.size
    if missing_salary_count.positive?
      period_label = "#{Date::MONTHNAMES[@month_int]} #{@year_int}"
      return Result.new(
        success?: false,
        error_message: "Cannot calculate salaries: #{missing_salary_count} employee(s) do not have an applicable salary record on or before #{as_of_date.strftime('%B %d, %Y')}. No partial salaries created."
      )
    end

    # Handle existing zero-value Pending records appropriately so they become Not Payable
    MonthlySalary.where(period_id: period.id, status: MonthlySalary::STATUS_PENDING)
                 .where("payable_amount <= 0")
                 .update_all(status: MonthlySalary::STATUS_NOT_PAYABLE, updated_at: Time.current)

    # 3. Check existing MonthlySalary records for idempotency.
    existing_employee_ids = MonthlySalary.where(period_id: period.id).pluck(:employee_id).to_set
    preserved_count = existing_employee_ids.size

    # If all employees already have salary records for this period
    if preserved_count == total_employees
      currency_totals = calculate_currency_totals(period.id)
      return Result.new(
        success?: true,
        period: period,
        total_employees: total_employees,
        calculated_count: 0,
        preserved_count: preserved_count,
        currency_totals: currency_totals
      )
    end

    calculated_count = 0
    now = Time.current

    # 4. Perform atomic bulk insertion
    ActiveRecord::Base.transaction do
      Employee.select(:id).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        records_to_insert = []

        batch.each do |employee|
          next if existing_employee_ids.include?(employee.id)

          joining_date = joining_dates_by_id[employee.id]
          annual_salary = salaries_by_employee_id[employee.id]
          working_days, present_days = attendances_by_employee_id[employee.id]

          # If this employee joined after the month ends they have no annual_salary
          # in the map. Treat them as zero-payable (eligible_days = 0 from attendance).
          # We still create a MonthlySalary record (with payable = 0) so the period
          # is considered fully calculated and salary processing can proceed.
          if joining_date && joining_date > month_end
            annual_salary ||= BigDecimal("0")
          end

          monthly_base, payable = compute_salary_amounts(annual_salary, working_days, present_days)

          status = payable <= BigDecimal("0") ? MonthlySalary::STATUS_NOT_PAYABLE : MonthlySalary::STATUS_PENDING

          records_to_insert << {
            employee_id:    employee.id,
            period_id:      period.id,
            monthly_salary: monthly_base,
            payable_amount: payable,
            status:         status,
            created_at:     now,
            updated_at:     now
          }
        end

        next if records_to_insert.empty?

        MonthlySalary.insert_all(records_to_insert, unique_by: [ :employee_id, :period_id ])
        calculated_count += records_to_insert.size
      end

      currency_totals = calculate_currency_totals(period.id)

      Result.new(
        success?: true,
        period: period,
        total_employees: total_employees,
        calculated_count: calculated_count,
        preserved_count: preserved_count,
        currency_totals: currency_totals
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    Result.new(success?: false, error_message: "Database error during salary calculation: #{e.message}")
  end

  def self.compute_salary_amounts(annual_salary, working_days, present_days)
    new(year: 2026, month: 1).compute_salary_amounts(annual_salary, working_days, present_days)
  end

  def compute_salary_amounts(annual_salary, working_days, present_days)
    # Employees who joined after the month ends have no salary; record zero.
    annual_dec = BigDecimal(annual_salary.to_s)
    # monthly_base_salary = annual_salary / 12, rounded to 2 dp with HALF_UP.
    monthly_base = (annual_dec / BigDecimal("12")).round(2, :half_up)

    payable = if working_days.to_i <= 0 || present_days.to_i <= 0
      BigDecimal("0.00")
    else
      # payable_salary = monthly_base * present_days / eligible_working_days
      ((monthly_base * BigDecimal(present_days.to_s)) / BigDecimal(working_days.to_s)).round(2, :half_up)
    end

    [ monthly_base, payable ]
  end

  private

  def validate_inputs
    error = AttendanceGenerator.validate_period(@year, @month)
    return error if error

    @year_int  = @year.to_s.strip.to_i
    @month_int = @month.to_s.strip.to_i

    nil
  end

  def calculate_currency_totals(period_id)
    # Sum payable_amount grouped by country currency
    MonthlySalary.joins(employee: :country)
                 .where(period_id: period_id)
                 .group("countries.currency")
                 .sum(:payable_amount)
                 .transform_values { |val| BigDecimal(val.to_s).round(2, :half_up) }
  end
end
