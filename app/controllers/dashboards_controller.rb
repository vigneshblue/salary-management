class DashboardsController < ApplicationController
  def show
    @as_of_date = params[:as_of_date].presence ? Date.parse(params[:as_of_date]) : Date.current rescue Date.current

    @year = params[:year].presence&.to_i
    @month = params[:month].presence&.to_i

    @periods = Period.order(year: :desc, month: :desc)

    @insights = SalaryInsights.call(as_of_date: @as_of_date, year: @year, month: @month)
    @selected_period = @insights.selected_period
  end
end
