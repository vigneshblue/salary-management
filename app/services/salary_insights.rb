class SalaryInsights
  Result = Struct.new(
    :total_employees,
    :country_counts,
    :department_counts,
    :employees_with_salary_count,
    :salaries_by_country,
    :salaries_by_department,
    :selected_period,
    :period_paid_count,
    :period_paid_totals,
    :period_pending_count,
    :period_pending_totals,
    :recent_periods_trends,
    keyword_init: true
  )

  def self.call(as_of_date: Date.current, year: nil, month: nil)
    new(as_of_date: as_of_date, year: year, month: month).call
  end

  def initialize(as_of_date: Date.current, year: nil, month: nil)
    @as_of_date = as_of_date || Date.current
    @year = year
    @month = month
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

    # 2. Aggregations by Country
    # Country uniquely determines currency
    country_rows = current_salaries_scope
      .group("countries.name, countries.currency")
      .order("countries.name")
      .pluck(
        "countries.name",
        "countries.currency",
        Arel.sql("COUNT(employees.id)"),
        Arel.sql("MIN(latest_salaries.annual_salary)"),
        Arel.sql("MAX(latest_salaries.annual_salary)"),
        Arel.sql("AVG(latest_salaries.annual_salary)")
      )

    salaries_by_country = country_rows.map do |name, currency, count, min_s, max_s, avg_s|
      {
        country_name: name,
        currency: currency,
        count: count,
        min: min_s ? BigDecimal(min_s.to_s).round(2, :half_up) : BigDecimal("0.00"),
        max: max_s ? BigDecimal(max_s.to_s).round(2, :half_up) : BigDecimal("0.00"),
        avg: avg_s ? BigDecimal(avg_s.to_s).round(2, :half_up) : BigDecimal("0.00")
      }
    end

    # 3. Aggregations by Department & Currency
    # A single department can span multiple countries with different currencies
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

    # 4. Monthly Payroll Insights for Selected Period
    selected_period = find_target_period

    period_paid_count = 0
    period_paid_totals = {}
    period_pending_count = 0
    period_pending_totals = {}

    if selected_period
      paid_scope = selected_period.monthly_salaries.where(status: MonthlySalary::STATUS_PAID)
      period_paid_count = paid_scope.count
      period_paid_totals = paid_scope.joins(employee: :country)
                                     .group("countries.currency")
                                     .sum(:payable_amount)
                                     .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      pending_scope = selected_period.monthly_salaries.where(status: MonthlySalary::STATUS_PENDING)
      period_pending_count = pending_scope.count
      period_pending_totals = pending_scope.joins(employee: :country)
                                           .group("countries.currency")
                                           .sum(:payable_amount)
                                           .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }
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
      selected_period: selected_period,
      period_paid_count: period_paid_count,
      period_paid_totals: period_paid_totals,
      period_pending_count: period_pending_count,
      period_pending_totals: period_pending_totals,
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
