class MonthlySalariesController < ApplicationController
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

    if @current_period
      @salaries_count = @current_period.monthly_salaries.count
      @pending_count = @current_period.monthly_salaries.where(status: MonthlySalary::STATUS_PENDING).count
      @paid_count = @current_period.monthly_salaries.where(status: MonthlySalary::STATUS_PAID).count
      @attendances_count = @current_period.attendances.count

      @currency_totals = @current_period.monthly_salaries
                                        .joins(employee: :country)
                                        .group("countries.currency")
                                        .sum(:payable_amount)

      @currency_totals_paid = @current_period.monthly_salaries
                                             .where(status: MonthlySalary::STATUS_PAID)
                                             .joins(employee: :country)
                                             .group("countries.currency")
                                             .sum(:payable_amount)

      @currency_totals_pending = @current_period.monthly_salaries
                                                .where(status: MonthlySalary::STATUS_PENDING)
                                                .joins(employee: :country)
                                                .group("countries.currency")
                                                .sum(:payable_amount)

      @sample_salaries = @current_period.monthly_salaries
                                        .includes(employee: [ :country, :department ])
                                        .limit(10)
    else
      @salaries_count = 0
      @pending_count = 0
      @paid_count = 0
      @attendances_count = 0
      @currency_totals = {}
      @currency_totals_paid = {}
      @currency_totals_pending = {}
      @sample_salaries = []
    end
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
end
