class MonthlySalariesController < ApplicationController
  DEFAULT_PER_PAGE = 25

  def index
    @periods = Period.order(year: :desc, month: :desc)
    current_date = Date.current

    if params[:year].present? || params[:month].present?
      if AttendanceGenerator.valid_date?(params[:year], params[:month])
        @year = params[:year].to_i
        @month = params[:month].to_i
      else
        @year = current_date.year
        @month = current_date.month
        flash.now[:alert] = AttendanceGenerator.validate_period(params[:year], params[:month])
      end
    else
      @year = current_date.year
      @month = current_date.month
    end

    @current_period = Period.find_by(year: @year, month: @month)
    @total_employees = Employee.count

    # Filter parameters
    @query = params[:q].to_s.strip
    @country_id = params[:country_id].presence
    @department_id = params[:department_id].presence
    @status = params[:status].presence # "Pending" or "Paid"
    @currency = CurrencyConverter.normalize_currency(params[:currency])
    @supported_currencies = CurrencyConverter::SUPPORTED_CURRENCIES

    @countries = Country.order(:name)
    @departments = Department.order(:name)

    @page = [ params[:page].to_i, 1 ].max
    @per_page = params[:per_page].present? ? [ params[:per_page].to_i, 1 ].max : DEFAULT_PER_PAGE

    if @current_period
      @salaries_count = @current_period.monthly_salaries.count
      @pending_count = @current_period.monthly_salaries.where(status: MonthlySalary::STATUS_PENDING).count
      @paid_count = @current_period.monthly_salaries.where(status: MonthlySalary::STATUS_PAID).count
      @not_payable_count = @current_period.monthly_salaries.where(status: MonthlySalary::STATUS_NOT_PAYABLE).count
      @attendances_count = @current_period.attendances.count

      # Complete relevant period dataset summaries
      @currency_totals = @current_period.monthly_salaries
                                        .joins(employee: :country)
                                        .group("countries.currency")
                                        .sum(:payable_amount)
                                        .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      @currency_totals_paid = @current_period.monthly_salaries
                                             .where(status: MonthlySalary::STATUS_PAID)
                                             .joins(employee: :country)
                                             .group("countries.currency")
                                             .sum(:payable_amount)
                                             .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      @currency_totals_pending = @current_period.monthly_salaries
                                                .where(status: MonthlySalary::STATUS_PENDING)
                                                .joins(employee: :country)
                                                .group("countries.currency")
                                                .sum(:payable_amount)
                                                .transform_values { |v| BigDecimal(v.to_s).round(2, :half_up) }

      # Converted total payable using reporting currency
      @total_payable_converted = BigDecimal(
        @currency_totals.sum(BigDecimal("0.0")) do |curr, amount|
          CurrencyConverter.convert(amount, from: curr, to: @currency)
        end.to_s
      ).round(2, :half_up)

      @total_paid_converted = BigDecimal(
        @currency_totals_paid.sum(BigDecimal("0.0")) do |curr, amount|
          CurrencyConverter.convert(amount, from: curr, to: @currency)
        end.to_s
      ).round(2, :half_up)

      @total_pending_converted = BigDecimal(
        @currency_totals_pending.sum(BigDecimal("0.0")) do |curr, amount|
          CurrencyConverter.convert(amount, from: curr, to: @currency)
        end.to_s
      ).round(2, :half_up)

      # Build query scope for paginated table
      base_scope = @current_period.monthly_salaries
                                  .joins(employee: [ :country, :department ])
                                  .order("employees.employee_number ASC")

      scope = base_scope

      if @query.present?
        pattern = "%#{sanitize_sql_like(@query)}%"
        scope = scope.where(
          "employees.employee_number ILIKE :pattern OR employees.name ILIKE :pattern",
          pattern: pattern
        )
      end

      scope = scope.where("employees.country_id = ?", @country_id) if @country_id.present?
      scope = scope.where("employees.department_id = ?", @department_id) if @department_id.present?
      scope = scope.where(status: @status) if @status.present?

      @total_count = scope.count
      @total_pages = (@total_count.to_f / @per_page).ceil
      @total_pages = 1 if @total_pages.zero?

      @from_index = if @total_count.zero? || @page > @total_pages
        0
      else
        ((@page - 1) * @per_page) + 1
      end

      @to_index = if @total_count.zero? || @page > @total_pages
        0
      else
        [ @page * @per_page, @total_count ].min
      end

      # Preload associations to avoid N+1 queries.
      # To show annual salary and attendance days:
      # - employee.salaries are preloaded and current_salary(as_of) is fetched in memory
      # - attendances for this period are loaded in a batch hash map for the page records
      @monthly_salaries = scope.includes(employee: [ :country, :department, :salaries ])
                               .limit(@per_page)
                               .offset((@page - 1) * @per_page)
                               .to_a

      emp_ids = @monthly_salaries.map(&:employee_id)
      @attendances_by_emp_id = if emp_ids.any?
        @current_period.attendances.where(employee_id: emp_ids).index_by(&:employee_id)
      else
        {}
      end

      @as_of_date = Date.new(@year, @month, 1)
    else
      @salaries_count = 0
      @pending_count = 0
      @paid_count = 0
      @not_payable_count = 0
      @attendances_count = 0
      @currency_totals = {}
      @currency_totals_paid = {}
      @currency_totals_pending = {}
      @total_payable_converted = BigDecimal("0.00")
      @total_paid_converted = BigDecimal("0.00")
      @total_pending_converted = BigDecimal("0.00")

      @total_count = 0
      @total_pages = 1
      @from_index = 0
      @to_index = 0
      @monthly_salaries = []
      @attendances_by_emp_id = {}
      @as_of_date = Date.current
    end

    @filter_params = {
      year: @year,
      month: @month,
      q: @query.presence,
      country_id: @country_id,
      department_id: @department_id,
      status: @status,
      currency: (@currency if @currency != CurrencyConverter::DEFAULT_CURRENCY)
    }.compact
  end

  def create
    year = params[:year]
    month = params[:month]

    if year.blank? || month.blank?
      flash[:alert] = "Please provide both year and month."
      redirect_to monthly_salaries_path(year: year, month: month)
      return
    end

    result = SalaryCalculator.call(year: year, month: month)

    if result.success?
      period_label = "#{Date::MONTHNAMES[result.period.month]} #{result.period.year}"

      if result.total_employees.zero?
        flash[:notice] = "No employees found in the system to calculate salaries for."
      elsif result.calculated_count.positive? && result.preserved_count.positive?
        flash[:notice] = "Calculated #{helpers.number_with_delimiter(result.calculated_count)} new monthly salary records for #{period_label}. Preserved #{helpers.number_with_delimiter(result.preserved_count)} existing records."
      elsif result.calculated_count.positive?
        flash[:notice] = "Successfully calculated monthly salaries for all #{helpers.number_with_delimiter(result.calculated_count)} employees for #{period_label}."
      else
        flash[:notice] = "Monthly salaries for #{period_label} have already been calculated. All #{helpers.number_with_delimiter(result.preserved_count)} existing records were preserved (0 new records created)."
      end
    else
      flash[:alert] = result.error_message
    end

    redirect_to monthly_salaries_path(year: year, month: month)
  end

  def process_salaries
    year = params[:year]
    month = params[:month]

    if year.blank? || month.blank?
      flash[:alert] = "Please provide both year and month."
      redirect_to monthly_salaries_path(year: year, month: month)
      return
    end

    result = SalaryProcessor.call(year: year, month: month)

    if result.success?
      period_label = "#{Date::MONTHNAMES[result.period.month]} #{result.period.year}"

      if result.processed_count.positive?
        totals_summary = result.currency_totals.map do |currency, total|
          symbol = EmployeesHelper::CURRENCY_SYMBOLS[currency] || "#{currency} "
          "#{symbol}#{helpers.number_with_precision(total, precision: 2, delimiter: ',')}"
        end.join(", ")

        totals_text = totals_summary.present? ? " (Total: #{totals_summary})" : ""
        flash[:notice] = "Successfully processed #{helpers.number_with_delimiter(result.processed_count)} pending salaries for #{period_label}#{totals_text}."
      elsif result.already_paid_count.positive?
        flash[:notice] = "All salaries for #{period_label} are already processed and marked as Paid (0 pending records newly processed)."
      else
        flash[:alert] = "No pending salary records found to process for #{period_label}."
      end
    else
      flash[:alert] = result.error_message
    end

    redirect_to monthly_salaries_path(year: year, month: month)
  end

  private

  def sanitize_sql_like(str)
    str.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end
end
