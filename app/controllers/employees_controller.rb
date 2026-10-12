class EmployeesController < ApplicationController
  DEFAULT_PER_PAGE = 10

  def index
    @page = [ params[:page].to_i, 1 ].max
    @per_page = params[:per_page].present? ? [ params[:per_page].to_i, 1 ].max : DEFAULT_PER_PAGE

    # Permitted search/filter parameters, preserved across pagination
    @query = params[:q].to_s.strip
    @country_id = params[:country_id].presence
    @department_id = params[:department_id].presence

    # Build the scope with search and filters applied at the database level
    scope = filtered_scope

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

    @employees = scope
      .includes(:country, :department, :salaries)
      .limit(@per_page)
      .offset((@page - 1) * @per_page)

    # Expose for dropdown population
    @countries = Country.order(:name)
    @departments = Department.order(:name)

    # Hash of active filter params to pass through pagination links
    @filter_params = {
      q: @query.presence,
      country_id: @country_id,
      department_id: @department_id
    }.compact
  end

  def show
    @employee = Employee.includes(:country, :department).find(params[:id])
    @salaries = @employee.salaries.order(effective_from: :desc).to_a
    @attendances = @employee.attendances.includes(:period).order("periods.year DESC, periods.month DESC").to_a
    @monthly_salaries = @employee.monthly_salaries.includes(:period).order("periods.year DESC, periods.month DESC").to_a

    # We pass the pre-sorted and fetched salaries to a temporary in-memory
    # collection for current_salary if it needs it, or just use current_salary.
    # Since current_salary queries the DB if salaries aren't loaded, let's load them explicitly.
    @employee.association(:salaries).target = @salaries
  end

  def new
    @employee = Employee.new
    @countries = Country.order(:name)
    @departments = Department.order(:name)
    @salary_effective_from = Date.current
  end

  def create
    @employee = Employee.new(employee_params)
    @countries = Country.order(:name)
    @departments = Department.order(:name)

    @initial_salary = params.dig(:employee, :initial_salary).presence
    @salary_effective_from = params.dig(:employee, :salary_effective_from).presence

    @salary = @employee.salaries.build(
      annual_salary: @initial_salary,
      effective_from: @salary_effective_from
    )

    employee_valid = @employee.valid?
    salary_valid = @salary.valid?

    if employee_valid && salary_valid
      ActiveRecord::Base.transaction do
        @employee.save!
        @salary.save!
      end
      redirect_to employee_path(@employee), notice: "Employee created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @employee = Employee.find(params[:id])
    @countries = Country.order(:name)
    @departments = Department.order(:name)
  end

  def update
    @employee = Employee.find(params[:id])
    @countries = Country.order(:name)
    @departments = Department.order(:name)

    @employee.assign_attributes(employee_params)

    @salary_amount = params.dig(:employee, :new_salary).presence
    @salary_effective_from = params.dig(:employee, :salary_effective_from).presence

    salary_submitted = @salary_amount.present? || @salary_effective_from.present?

    if salary_submitted
      @new_salary = @employee.salaries.build(
        annual_salary: @salary_amount,
        effective_from: @salary_effective_from
      )
    end

    employee_valid = @employee.valid?
    salary_valid = !salary_submitted || @new_salary.valid?

    if employee_valid && salary_valid
      ActiveRecord::Base.transaction do
        @employee.save!
        @new_salary&.save!
      end
      redirect_to employee_path(@employee), notice: "Employee updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def employee_params
    params.require(:employee).permit(:employee_number, :name, :country_id, :department_id, :joining_date)
  end

  def filtered_scope
    scope = Employee.order(:employee_number)

    if @query.present?
      pattern = "%#{sanitize_sql_like(@query)}%"
      scope = scope.where(
        "employees.employee_number ILIKE :pattern OR employees.name ILIKE :pattern",
        pattern: pattern
      )
    end

    scope = scope.where(country_id: @country_id) if @country_id.present?
    scope = scope.where(department_id: @department_id) if @department_id.present?

    scope
  end

  def sanitize_sql_like(str)
    str.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end
end
