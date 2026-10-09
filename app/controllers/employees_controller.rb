class EmployeesController < ApplicationController
  DEFAULT_PER_PAGE = 10

  def index
    @page = [ params[:page].to_i, 1 ].max
    @per_page = params[:per_page].present? ? [ params[:per_page].to_i, 1 ].max : DEFAULT_PER_PAGE

    scope = Employee.order(:employee_number)
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
  end
end
