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

  private

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
