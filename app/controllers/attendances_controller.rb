class AttendancesController < ApplicationController
  def index
    # Default to current period on initial load or if invalid params given
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
    @working_days = AttendanceGenerator.calculate_working_days(@year, @month)

    if @current_period
      @attendances_count = @current_period.attendances.count
      # Grab sample attendances for review if any
      @sample_attendances = @current_period.attendances.includes(employee: [ :country, :department ]).limit(10)
    else
      @attendances_count = 0
      @sample_attendances = []
    end
  end

  def new
    redirect_to attendances_path
  end

  def create
    year = params[:year]
    month = params[:month]

    if year.blank? || month.blank?
      flash[:alert] = "Please provide both year and month."
      redirect_to attendances_path(year: year, month: month)
      return
    end

    result = AttendanceGenerator.call(year: year, month: month)

    if result.success?
      period_label = "#{Date::MONTHNAMES[result.period.month]} #{result.period.year}"

      if result.total_employees.zero?
        flash[:notice] = "Period #{period_label} created. No employees found in the system to generate attendance for."
      elsif result.generated_count.positive? && result.preserved_count.positive?
        flash[:notice] = "Generated #{helpers.number_with_delimiter(result.generated_count)} new attendance records for #{period_label} (#{result.working_days} working days). Preserved #{helpers.number_with_delimiter(result.preserved_count)} existing attendance records."
      elsif result.generated_count.positive?
        flash[:notice] = "Successfully generated attendance for all #{helpers.number_with_delimiter(result.generated_count)} employees for #{period_label} (#{result.working_days} working days)."
      else
        flash[:notice] = "Attendance for #{period_label} already exists. All #{helpers.number_with_delimiter(result.preserved_count)} existing records were preserved (0 new records generated)."
      end
    else
      flash[:alert] = result.error_message
    end

    redirect_to attendances_path(year: year, month: month)
  end
end
