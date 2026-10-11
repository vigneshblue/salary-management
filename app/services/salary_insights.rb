class SalaryInsights
  Result = Struct.new(
    :total_employees,
    :country_counts,
    :department_counts,
    :employees_with_salary_count,
    :salaries_by_country,
    :salaries_by_department,
    :salaries_by_department_converted,
    :currency,
    :selected_period,
    :period_paid_count,
    :period_paid_totals,
    :period_paid_total_converted,
    :period_pending_count,
    :period_pending_totals,
    :period_pending_total_converted,
    :recent_periods_trends,
    keyword_init: true
  )

  def self.call(as_of_date: Date.current, year: nil, month: nil, currency: CurrencyConverter::DEFAULT_CURRENCY)
    new(as_of_date: as_of_date, year: year, month: month, currency: currency).call
  end

  def initialize(as_of_date: Date.current, year: nil, month: nil, currency: CurrencyConverter::DEFAULT_CURRENCY)
    @as_of_date = as_of_date || Date.current
    @year = year
    @month = month
    @currency = CurrencyConverter.normalize_currency(currency)
  end

  def call
    total_employees = Employee.count
    country_counts = Employee.joins(:country).group("countries.name").order("countries.name").count
    department_counts = Employee.joins(:department).group("departments.name").order("departments.name").count

    # 1. Base current salary subquery per employee:
    # Latest salary record with effective_from <= as_of_date
    latest_salary_subquery = Salary.where("effective_from <= ?", @as_of_date)
                                   .select("DISTINCT ON (employee_id) employee_id, annual_salary, effective_from")
                                   .order("employee_id, effective_from DESC")

    # Joined with employee, country, and department
    current_salaries_scope = Employee.joins("INNER JOIN (#{latest_salary_subquery.to_sql}) latest_salaries ON latest_salaries.employee_id = employees.id")
                                     .joins(:country, :department)

    employees_with_salary_count = current_salaries_scope.count

    # 2. Aggregations by Country in Selected Reporting Currency
    # Convert each employee's applicable salary to the selected reporting currency before calculating min, max, avg.
    country_salary_rows = current_salaries_scope
      .pluck("countries.name", "countries.currency", "latest_salaries.annual_salary")

    salaries_by_country_name = Hash.new { |h, k| h[k] = [] }
    country_salary_rows.each do |c_name, emp_curr, annual_salary|
      converted_amount = CurrencyConverter.convert(annual_salary, from: emp_curr, to: @currency)
      salaries_by_country_name[c_name] << converted_amount
    end

    all_country_names = Country.order(:name).pluck(:name)
    salaries_by_country = all_country_names.map do |c_name|
      converted_salaries = salaries_by_country_name[c_name] || []
      next if converted_salaries.empty?

      count = converted_salaries.size
      min_s = BigDecimal(converted_salaries.min.to_s).round(2, :half_up)
      max_s = BigDecimal(converted_salaries.max.to_s).round(2, :half_up)
      sum_s = converted_salaries.sum(BigDecimal("0.0"))
      avg_s = (BigDecimal(sum_s.to_s) / count).round(2, :half_up)

      {
        country_name: c_name,
        currency: @currency,
        count: count,
        min: min_s,
        max: max_s,
        avg: avg_s
      }
    end.compact

    # 3. Aggregations by Department & Currency (legacy/per-currency)
    department_rows = current_salaries_scope
      .group("departments.name, countries.currency")
      .order("departments.name, countries.currency")
      .pluck(
        "departments.name",
        "countries.currency",
        Arel.sql("COUNT(employees.id)"),
        Arel.sql("MIN(latest_salaries.annual_salary)"),
        Arel.sql("MAX(latest_salaries.annual_salary)"),
        Arel.sql("AVG(latest_salaries.annual_salary)")
      )

    salaries_by_department = department_rows.map do |dept_name, currency, count, min_s, max_s, avg_s|
      {
        department_name: dept_name,
        currency: currency,
        count: count,
        min: min_s ? BigDecimal(min_s.to_s).round(2, :half_up) : BigDecimal("0.00"),
        max: max_s ? BigDecimal(max_s.to_s).round(2, :half_up) : BigDecimal("0.00"),
        avg: avg_s ? BigDecimal(avg_s.to_s).round(2, :half_up) : BigDecimal("0.00")
      }
    end

    # 3b. Department breakdown converted into the selected reporting currency
    # Individual employee salaries are converted before calculating min, max, avg.
    dept_converted_rows = current_salaries_scope
      .pluck("departments.name", "countries.currency", "latest_salaries.annual_salary")

    # Group converted values by department name
    salaries_by_dept_name = Hash.new { |h, k| h[k] = [] }
    dept_converted_rows.each do |dept_name, emp_curr, annual_salary|
      converted_amount = CurrencyConverter.convert(annual_salary, from: emp_curr, to: @currency)
      salaries_by_dept_name[dept_name] << converted_amount
    end

    # Build sorted results for each department with employees
    all_dept_names = Department.order(:name).pluck(:name)
    salaries_by_department_converted = all_dept_names.map do |dept_name|
      converted_salaries = salaries_by_dept_name[dept_name] || []
      next if converted_salaries.empty?

      count = converted_salaries.size
      min_s = BigDecimal(converted_salaries.min.to_s).round(2, :half_up)
      max_s = BigDecimal(converted_salaries.max.to_s).round(2, :half_up)
      sum_s = converted_salaries.sum(BigDecimal("0.0"))
      avg_s = (BigDecimal(sum_s.to_s) / count).round(2, :half_up)

      {
        department_name: dept_name,
        currency: @currency,
        count: count,
        min: min_s,
        max: max_s,
        avg: avg_s
      }
    end.compact

    # 4. Monthly Payroll Insights for Selected Period
    selected_period = find_target_period

    period_paid_count = 0
    period_paid_totals = {}
    period_paid_total_converted = BigDecimal("0.00")
    period_pending_count = 0
    period_pending_totals = {}
    period_pending_total_converted = BigDecimal("0.00")

    if selected_period
      paid_scope = selected_period.monthly_salaries.where(status: MonthlySalary::STATUS_PAID)
      period_paid_count = paid_scope.count
      period_paid_totals = paid_scope.joins(employee: :country)
                                     .group("countries.currency")
                                     .sum(:payable_amount)
                                     .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      period_paid_total_converted = BigDecimal(
        period_paid_totals.sum(BigDecimal("0.0")) do |curr, amount|
          CurrencyConverter.convert(amount, from: curr, to: @currency)
        end.to_s
      ).round(2, :half_up)

      pending_scope = selected_period.monthly_salaries.where(status: MonthlySalary::STATUS_PENDING)
      period_pending_count = pending_scope.count
      period_pending_totals = pending_scope.joins(employee: :country)
                                           .group("countries.currency")
                                           .sum(:payable_amount)
                                           .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      period_pending_total_converted = BigDecimal(
        period_pending_totals.sum(BigDecimal("0.0")) do |curr, amount|
          CurrencyConverter.convert(amount, from: curr, to: @currency)
        end.to_s
      ).round(2, :half_up)
    end

    # 5. Recent Monthly Payroll Trends (up to last 6 periods with recorded salaries)
    recent_periods = Period.joins(:monthly_salaries)
                           .distinct
                           .order(year: :desc, month: :desc)
                           .limit(6)

    recent_periods_trends = recent_periods.map do |period|
      paid_count = period.monthly_salaries.where(status: MonthlySalary::STATUS_PAID).count
      pending_count = period.monthly_salaries.where(status: MonthlySalary::STATUS_PENDING).count
      total_count = period.monthly_salaries.count

      paid_by_currency = period.monthly_salaries
                               .where(status: MonthlySalary::STATUS_PAID)
                               .joins(employee: :country)
                               .group("countries.currency")
                               .sum(:payable_amount)
                               .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      total_by_currency = period.monthly_salaries
                                .joins(employee: :country)
                                .group("countries.currency")
                                .sum(:payable_amount)
                                .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      {
        period: period,
        year: period.year,
        month: period.month,
        period_name: "#{Date::MONTHNAMES[period.month]} #{period.year}",
        total_count: total_count,
        paid_count: paid_count,
        pending_count: pending_count,
        paid_by_currency: paid_by_currency,
        total_by_currency: total_by_currency
      }
    end

    Result.new(
      total_employees: total_employees,
      country_counts: country_counts,
      department_counts: department_counts,
      employees_with_salary_count: employees_with_salary_count,
      salaries_by_country: salaries_by_country,
      salaries_by_department: salaries_by_department,
      salaries_by_department_converted: salaries_by_department_converted,
      currency: @currency,
      selected_period: selected_period,
      period_paid_count: period_paid_count,
      period_paid_totals: period_paid_totals,
      period_paid_total_converted: period_paid_total_converted,
      period_pending_count: period_pending_count,
      period_pending_totals: period_pending_totals,
      period_pending_total_converted: period_pending_total_converted,
      recent_periods_trends: recent_periods_trends
    )
  end

  private

  def find_target_period
    if @year.present? && @month.present?
      Period.find_by(year: @year.to_i, month: @month.to_i)
    else
      # Default to latest period with monthly salaries or latest period overall
      Period.joins(:monthly_salaries).order(year: :desc, month: :desc).first || Period.order(year: :desc, month: :desc).first
    end
  end
end
