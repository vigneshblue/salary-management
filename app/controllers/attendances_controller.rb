class AttendancesController < ApplicationController
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
    @working_days = AttendanceGenerator.calculate_working_days(@year, @month)

    # Filter parameters
    @query = params[:q].to_s.strip
    @country_id = params[:country_id].presence
    @department_id = params[:department_id].presence
    @status = params[:status].presence # "all_present", "perfect", "partial", "absent", "ineligible"

    @countries = Country.order(:name)
    @departments = Department.order(:name)

    @page = [ params[:page].to_i, 1 ].max
    @per_page = params[:per_page].present? ? [ params[:per_page].to_i, 1 ].max : DEFAULT_PER_PAGE

    if @current_period
      @attendances_count = @current_period.attendances.count

      # Summary calculations across the complete dataset for this period
      base_scope = @current_period.attendances.joins(employee: [ :country, :department ])

      # Summary aggregates
      # Note: For employees who joined after month end, working_days = 0, present_days = 0 -> absent = 0
      # Perfect / full attendance: working_days > 0 AND present_days == working_days
      # Partial attendance: working_days > 0 AND present_days < working_days AND present_days > 0
      # Absent (no presence): working_days > 0 AND present_days == 0
      # Ineligible: working_days == 0
      @total_working_days_sum = base_scope.sum(:working_days)
      @total_present_days_sum = base_scope.sum(:present_days)
      @total_absent_days_sum  = base_scope.where("attendances.working_days > attendances.present_days")
                                          .sum("attendances.working_days - attendances.present_days")

      @overall_attendance_rate = if @total_working_days_sum.positive?
        ((@total_present_days_sum.to_f / @total_working_days_sum) * 100).round(1)
      else
        0.0
      end

      # Filtered scope for table
      scope = base_scope.order("employees.employee_number ASC")

      if @query.present?
        pattern = "%#{sanitize_sql_like(@query)}%"
        scope = scope.where(
          "employees.employee_number ILIKE :pattern OR employees.name ILIKE :pattern",
          pattern: pattern
        )
      end

      scope = scope.where("employees.country_id = ?", @country_id) if @country_id.present?
      scope = scope.where("employees.department_id = ?", @department_id) if @department_id.present?

      if @status.present?
        case @status
        when "perfect"
          scope = scope.where("attendances.working_days > 0 AND attendances.present_days = attendances.working_days")
        when "partial"
          scope = scope.where("attendances.working_days > 0 AND attendances.present_days < attendances.working_days AND attendances.present_days > 0")
        when "absent"
          scope = scope.where("attendances.working_days > 0 AND attendances.present_days = 0")
        when "ineligible"
          scope = scope.where("attendances.working_days = 0")
        end
      end

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

      @attendances = scope.includes(employee: [ :country, :department ])
                          .limit(@per_page)
                          .offset((@page - 1) * @per_page)
    else
      @attendances_count = 0
      @total_working_days_sum = 0
      @total_present_days_sum = 0
      @total_absent_days_sum = 0
      @overall_attendance_rate = 0.0

      @total_count = 0
      @total_pages = 1
      @from_index = 0
      @to_index = 0
      @attendances = []
    end

    @filter_params = {
      year: @year,
      month: @month,
      q: @query.presence,
      country_id: @country_id,
      department_id: @department_id,
      status: @status
    }.compact
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

  private

  def sanitize_sql_like(str)
    str.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end
end
