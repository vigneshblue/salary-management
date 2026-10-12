class SalaryProcessor
  Result = Struct.new(
    :success?,
    :period,
    :processed_count,
    :already_paid_count,
    :currency_totals,
    :error_message,
    keyword_init: true
  )

  def self.call(year:, month:)
    new(year: year, month: month).call
  end

  def initialize(year:, month:)
    @year = year
    @month = month
  end

  def call
    validation_error = validate_inputs
    return Result.new(success?: false, error_message: validation_error) if validation_error

    period = Period.find_by(year: @year_int, month: @month_int)
    unless period
      period_label = "#{Date::MONTHNAMES[@month_int]} #{@year_int}"
      return Result.new(success?: false, error_message: "Period #{period_label} does not exist.")
    end

    ActiveRecord::Base.transaction do
      # 1. Update any legacy zero-value Pending records to Not Payable so they are never marked Paid
      MonthlySalary.where(period_id: period.id, status: MonthlySalary::STATUS_PENDING)
                   .where("payable_amount <= 0")
                   .update_all(status: MonthlySalary::STATUS_NOT_PAYABLE, updated_at: Time.current)

      # 2. Lock eligible pending records (status: Pending AND payable_amount > 0)
      pending_records = MonthlySalary.where(period_id: period.id, status: MonthlySalary::STATUS_PENDING)
                                     .where("payable_amount > 0")
                                     .lock
                                     .to_a

      # Calculate currency totals from locked pending records
      currency_totals = if pending_records.any?
        pending_ids = pending_records.map(&:id)
        MonthlySalary.where(id: pending_ids)
                     .joins(employee: :country)
                     .group("countries.currency")
                     .sum(:payable_amount)
                     .transform_values { |val| BigDecimal(val.to_s).round(2, :half_up) }
      else
        {}
      end

      # Perform conditional update in bulk strictly for pending records with payable_amount > 0
      now = Time.current
      processed_count = MonthlySalary.where(period_id: period.id, status: MonthlySalary::STATUS_PENDING)
                                     .where("payable_amount > 0")
                                     .update_all(status: MonthlySalary::STATUS_PAID, updated_at: now)

      already_paid_count = MonthlySalary.where(period_id: period.id, status: MonthlySalary::STATUS_PAID).count - processed_count

      Result.new(
        success?: true,
        period: period,
        processed_count: processed_count,
        already_paid_count: already_paid_count,
        currency_totals: currency_totals
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    Result.new(success?: false, error_message: "Database error during salary processing: #{e.message}")
  end

  private

  def validate_inputs
    error = AttendanceGenerator.validate_period(@year, @month)
    return error if error

    @year_int = @year.to_s.strip.to_i
    @month_int = @month.to_s.strip.to_i

    nil
  end
end
