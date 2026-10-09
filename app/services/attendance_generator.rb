class AttendanceGenerator
  Result = Struct.new(:success?, :period, :working_days, :total_employees, :generated_count, :preserved_count, :error_message, keyword_init: true)

  BATCH_SIZE = 1_000

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

    working_days = calculate_working_days(@year_int, @month_int)
    total_employees = Employee.count

    if total_employees.zero?
      period = Period.find_or_create_by!(year: @year_int, month: @month_int)
      return Result.new(
        success?: true,
        period: period,
        working_days: working_days,
        total_employees: 0,
        generated_count: 0,
        preserved_count: 0
      )
    end

    ActiveRecord::Base.transaction do
      period = Period.find_or_create_by!(year: @year_int, month: @month_int)

      # Find existing employee IDs for this period to preserve existing attendance
      existing_employee_ids = Attendance.where(period_id: period.id).pluck(:employee_id).to_set
      preserved_count = existing_employee_ids.size

      generated_count = 0
      now = Time.current

      # Find missing employee IDs in batches
      Employee.select(:id).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        records_to_insert = []

        batch.each do |employee|
          next if existing_employee_ids.include?(employee.id)

          present_days = calculate_present_days(employee.id, @year_int, @month_int, working_days)

          records_to_insert << {
            employee_id: employee.id,
            period_id: period.id,
            working_days: working_days,
            present_days: present_days,
            created_at: now,
            updated_at: now
          }
        end

        next if records_to_insert.empty?

        # Use insert_all with on_duplicate: :skip for extra safety and idempotent insertion
        Attendance.insert_all(records_to_insert, unique_by: [ :employee_id, :period_id ])
        generated_count += records_to_insert.size
      end

      Result.new(
        success?: true,
        period: period,
        working_days: working_days,
        total_employees: total_employees,
        generated_count: generated_count,
        preserved_count: preserved_count
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    Result.new(success?: false, error_message: "Database error during attendance generation: #{e.message}")
  end

  def self.valid_date?(year, month)
    validate_period(year, month).nil?
  end

  def self.validate_period(year, month)
    return "Year and month cannot be blank." if year.blank? || month.blank?

    year_str = year.to_s.strip
    month_str = month.to_s.strip

    return "Year must be an integer." unless year_str =~ /\A-?\d+\z/
    return "Month must be an integer." unless month_str =~ /\A-?\d+\z/

    year_int = year_str.to_i
    month_int = month_str.to_i

    return "Year must be an integer greater than 1900." if year_int <= 1900
    return "Month must be between 1 and 12." unless (1..12).cover?(month_int)

    begin
      Date.new(year_int, month_int, 1)
    rescue Date::Error
      return "Invalid year or month date combination."
    end

    nil
  end

  def self.calculate_working_days(year, month)
    new(year: year, month: month).calculate_working_days(year, month)
  end

  def calculate_working_days(year, month)
    year_int = year.to_i
    month_int = month.to_i

    start_date = Date.new(year_int, month_int, 1)
    end_date = start_date.end_of_month

    (start_date..end_date).count { |date| !date.saturday? && !date.sunday? }
  end

  def self.calculate_present_days(employee_id, year, month, working_days)
    new(year: year, month: month).calculate_present_days(employee_id, year, month, working_days)
  end

  def calculate_present_days(employee_id, year, month, working_days)
    return 0 if working_days <= 0

    # Documented deterministic formula:
    # Uses Integer CRC32 hash of "emp_<id>_period_<year>_<month>" modulo 100 to produce a reproducible percentage.
    # We map this into [0.80, 1.00] base present rate with up to 4 days absence max, ensuring present_days <= working_days.
    # Specifically:
    # - 70% chance of full attendance (0 days absent)
    # - 15% chance of 1 day absent
    # - 10% chance of 2 days absent
    # - 5% chance of 3..5 days absent (capped at working_days)
    key = "emp_#{employee_id}_period_#{year}_#{month}"
    hash_val = Zlib.crc32(key) % 100

    absence = if hash_val < 70
      0
    elsif hash_val < 85
      1
    elsif hash_val < 95
      2
    else
      3 + (hash_val % 3) # 3, 4, or 5
    end

    present = working_days - absence
    [ [ present, 0 ].max, working_days ].min
  end

  private

  def validate_inputs
    error = self.class.validate_period(@year, @month)
    return error if error

    @year_int = @year.to_s.strip.to_i
    @month_int = @month.to_s.strip.to_i

    nil
  end
end
