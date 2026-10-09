module EmployeesHelper
  CURRENCY_SYMBOLS = {
    "USD" => "$",
    "INR" => "₹",
    "GBP" => "£",
    "EUR" => "€",
    "CAD" => "CAD ",
    "AUD" => "AUD ",
    "JPY" => "¥"
  }.freeze

  def format_salary(salary, country = nil)
    return content_tag(:span, "No salary record", class: "text-muted salary-fallback") if salary.nil?

    amount = salary.respond_to?(:annual_salary) ? salary.annual_salary : salary
    currency = country&.currency || (salary.respond_to?(:employee) && salary.employee&.country&.currency) || "USD"

    formatted_amount = if (amount.to_d % 1).zero?
      number_with_delimiter(amount.to_i)
    else
      number_with_precision(amount, precision: 2, delimiter: ",")
    end

    prefix = CURRENCY_SYMBOLS[currency] || "#{currency} "
    "#{prefix}#{formatted_amount}"
  end

  def pagination_page_numbers(current_page, total_pages, window: 2)
    return (1..total_pages).to_a if total_pages <= 7

    pages = []
    pages << 1

    left_bound = [ current_page - window, 2 ].max
    right_bound = [ current_page + window, total_pages - 1 ].min

    if left_bound > 2
      pages << :gap
    elsif left_bound == 2
      pages << 2
    end

    (left_bound..right_bound).each do |p|
      pages << p unless pages.include?(p)
    end

    if right_bound < total_pages - 1
      pages << :gap
    elsif right_bound == total_pages - 1
      pages << total_pages - 1 unless pages.include?(total_pages - 1)
    end

    pages << total_pages unless pages.include?(total_pages)
    pages
  end
end
