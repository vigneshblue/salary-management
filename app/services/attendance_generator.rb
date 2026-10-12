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

    # Full-month working days (used for reporting; individual eligible days are per-employee)
    full_working_days = calculate_working_days(@year_int, @month_int)
    total_employees = Employee.count

    if total_employees.zero?
      period = Period.find_or_create_by!(year: @year_int, month: @month_int)
      return Result.new(
        success?: true,
        period: period,
        working_days: full_working_days,
        total_employees: 0,
        generated_count: 0,
        preserved_count: 0
      )
    end

    month_start = Date.new(@year_int, @month_int, 1)
    month_end   = month_start.end_of_month

    ActiveRecord::Base.transaction do
      period = Period.find_or_create_by!(year: @year_int, month: @month_int)

      # Find existing employee IDs for this period to preserve existing attendance
      existing_employee_ids = Attendance.where(period_id: period.id).pluck(:employee_id).to_set
      preserved_count = existing_employee_ids.size

      generated_count = 0
      now = Time.current

      # Fetch joining dates in bulk to avoid N+1 inside the batch loop.
      # Map is loaded outside the batch block and reused for every batch.
      joining_dates = Employee.pluck(:id, :joining_date).to_h

      Employee.select(:id).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        records_to_insert = []

        batch.each do |employee|
          next if existing_employee_ids.include?(employee.id)

          joining_date = joining_dates[employee.id]

          # Employee's eligible working days:
          # Start from the later of month_start or joining_date;
          # if the employee joins after the month ends, eligible_days = 0.
          eligible_days = eligible_working_days(joining_date, month_start, month_end)
          present_days  = calculate_present_days(employee.id, @year_int, @month_int, eligible_days)

          records_to_insert << {
            employee_id:  employee.id,
            period_id:    period.id,
            working_days: eligible_days,
            present_days: present_days,
            created_at:   now,
            updated_at:   now
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
        working_days: full_working_days,   # reported working days remain full-month for display
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

    year_str  = year.to_s.strip
    month_str = month.to_s.strip

    return "Year must be an integer."  unless year_str  =~ /\A-?\d+\z/
    return "Month must be an integer." unless month_str =~ /\A-?\d+\z/

    year_int  = year_str.to_i
    month_int = month_str.to_i

    return "Year must be an integer greater than 1900." if year_int <= 1900
    return "Month must be between 1 and 12."           unless (1..12).cover?(month_int)

    begin
      Date.new(year_int, month_int, 1)
    rescue Date::Error
      return "Invalid year or month date combination."
    end

    nil
  end

  # Returns the full-month working-day count (weekdays only).
  # Used for reporting/display and as the baseline for employees
  # who joined before or on the first day of the month.
  def self.calculate_working_days(year, month)
    new(year: year, month: month).calculate_working_days(year, month)
  end

  def calculate_working_days(year, month)
    year_int  = year.to_i
    month_int = month.to_i

    start_date = Date.new(year_int, month_int, 1)
    end_date   = start_date.end_of_month

    (start_date..end_date).count { |date| !date.saturday? && !date.sunday? }
  end

  # Returns the number of eligible weekday working days for an employee
  # given their joining_date and the selected month's boundaries.
  #
  # Rules:
  #   - Employee joined before the month starts  → full month's working days
  #   - Employee joined on or during the month   → weekdays from joining_date through month_end
  #   - Employee joins after the month ends      → 0 eligible days
  #
  # Note: If an employee's joining_date is a weekend, the count still starts
  # from that date; only actual weekdays within the range are counted.
  # Historical attendance records are NOT retroactively corrected when a
  # joining_date changes after generation — those records must be corrected manually.
  def self.eligible_working_days(joining_date, month_start, month_end)
    new(year: month_start.year, month: month_start.month)
      .eligible_working_days(joining_date, month_start, month_end)
  end

  def eligible_working_days(joining_date, month_start, month_end)
    return calculate_working_days(month_start.year, month_start.month) if joining_date.nil? || joining_date <= month_start
    return 0 if joining_date > month_end

    # Mid-month joiner: count weekdays from joining_date through month_end
    (joining_date..month_end).count { |date| !date.saturday? && !date.sunday? }
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
    key      = "emp_#{employee_id}_period_#{year}_#{month}"
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

    @year_int  = @year.to_s.strip.to_i
    @month_int = @month.to_s.strip.to_i

    nil
  end
end
