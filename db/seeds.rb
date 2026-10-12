# Deterministic seed data for ACME Salary Management
puts "== Seeding ACME Salary Management database =="

# 1. Countries (5 countries as defined in requirements and mock UI)
countries_data = [
  { name: "India", code: "IN", currency: "INR" },
  { name: "United States", code: "US", currency: "USD" },
  { name: "United Kingdom", code: "GB", currency: "GBP" },
  { name: "Canada", code: "CA", currency: "CAD" },
  { name: "Australia", code: "AU", currency: "AUD" }
]

countries_by_code = {}
countries_data.each do |cdata|
  country = Country.find_or_create_by!(code: cdata[:code]) do |c|
    c.name = cdata[:name]
    c.currency = cdata[:currency]
  end
  # Ensure attributes are up to date if record already existed
  country.update!(name: cdata[:name], currency: cdata[:currency]) if country.name != cdata[:name] || country.currency != cdata[:currency]
  countries_by_code[cdata[:code]] = country
end
puts "Seeded #{countries_by_code.size} countries."

# 2. Departments
departments_data = [
  "Engineering",
  "Product",
  "Marketing",
  "Sales",
  "Finance",
  "Operations",
  "HR"
]

departments_by_name = {}
departments_data.each do |dept_name|
  dept = Department.find_or_create_by!(name: dept_name)
  departments_by_name[dept_name] = dept
end
puts "Seeded #{departments_by_name.size} departments."

# Weighted department distribution (must sum to 100):
#   Engineering 28% | Sales 20% | Operations 16% | Marketing 12%
#   Product 10%     | Finance 8% | HR 6%
# Stored as cumulative upper bounds for a [0, 99] bucket lookup.
DEPT_WEIGHTS = [
  { name: "Engineering", cum: 28 },
  { name: "Sales",       cum: 48 },
  { name: "Operations",  cum: 64 },
  { name: "Marketing",   cum: 76 },
  { name: "Product",     cum: 86 },
  { name: "Finance",     cum: 94 },
  { name: "HR",          cum: 100 }
].freeze

# Returns a department object deterministically for a given 1-based employee index.
# Uses a multiplicative hash so results are identical on every run with no PRNG state.
def pick_department(emp_idx, departments_by_name)
  bucket = (emp_idx * 2_654_435_761) % 100
  weight = DEPT_WEIGHTS.find { |w| bucket < w[:cum] }
  departments_by_name[weight[:name]]
end

# 3. Deterministic Names for 5 Regions
names_by_country = {
  "IN" => {
    first: %w[Aarav Priya Rohan Ananya Rajesh Deepa Vikram Pooja Arun Sunita Amit Kavita Suresh Meera Rahul Neha Sanjay Anita Vivek Divya],
    last: %w[Kumar Patel Sharma Singh Verma Gupta Reddy Nair Joshi Rao Mehta Bhat Iyer Kulkarni Pillai Deshmukh Menon Bose Das Choudhury]
  },
  "US" => {
    first: %w[James Mary John Patricia Robert Jennifer Michael Linda David Elizabeth William Barbara Richard Susan Joseph Jessica Thomas Sarah Charles Karen],
    last: %w[Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin]
  },
  "GB" => {
    first: %w[Oliver Olivia George Amelia Harry Isla Jack Ava Charlie Emily Jacob Lily Thomas Sophia Oscar Mia James Ella William Grace],
    last: %w[Taylor Wilson Davies Evans Thomas Roberts Walker Wright Robinson Thompson White Edwards Hughes Green Hall Wood Harris Lewis Martin Jackson]
  },
  "CA" => {
    first: %w[Liam Emma Noah Charlotte Lucas Chloe Benjamin Sophie William Mia Logan Zoe Alexander Camille Ethan Lea Gabriel Juliette Samuel Florence],
    last: %w[Tremblay Roy Gagnon Bouchard Cote Morin Belanger Fortin Pelletier Gauthier Lemieux Bergeron Caron Ouellet Simard Leblanc Girard Denis Fontaine Vachon]
  },
  "AU" => {
    first: %w[Jack Charlotte William Olivia Noah Mia Thomas Isla Lucas Amelia Oliver Harper Henry Evelyn Mason Ava Harrison Ella Leo Chloe],
    last: %w[Kelly Ryan Murphy Martin Clarke Johnston White O'Brien Anderson Walsh O'Connor Sullivan McCarthy Palmer Mills King Hughes Butler Wright Mitchell]
  }
}

# Country distributions matching mock UI insights:
# India: 4,000 | US: 2,000 | UK: 1,500 | Canada: 1,500 | Australia: 1,000 => Total 10,000
country_allocations = [
  { code: "IN", count: 4000, base_salary: 3_000_000, salary_step: 75_000 },
  { code: "US", count: 2000, base_salary: 120_000, salary_step: 2_500 },
  { code: "GB", count: 1500, base_salary: 95_000, salary_step: 2_000 },
  { code: "CA", count: 1500, base_salary: 110_000, salary_step: 2_200 },
  { code: "AU", count: 1000, base_salary: 125_000, salary_step: 2_500 }
]

now = Time.current
total_target_employees = 10_000
employee_records = []
salary_blueprints = []

current_emp_idx = 1
country_allocations.each do |alloc|
  country = countries_by_code[alloc[:code]]
  names = names_by_country[alloc[:code]]

  alloc[:count].times do |c_idx|
    emp_num = format("EMP%05d", current_emp_idx)

    f_name = names[:first][(current_emp_idx + c_idx) % names[:first].size]
    l_name = names[:last][((current_emp_idx * 7) + c_idx) % names[:last].size]
    full_name = "#{f_name} #{l_name}"

    # Department distribution — weighted, deterministic
    dept = pick_department(current_emp_idx, departments_by_name)
    # Deterministic joining dates spread across the last 5 years
    joining_date = Date.new(2021, 1, 1) + ((current_emp_idx * 137) % (Date.current - Date.new(2021, 1, 1)).to_i)
    employee_records << {
      employee_number: emp_num,
      name: full_name,
      country_id: country.id,
      department_id: dept.id,
      joining_date: joining_date,
      created_at: now,
      updated_at: now
    }

    # Deterministic salary progression based on employee index
    salary_variation = ((c_idx % 21) - 10) * alloc[:salary_step]
    current_annual_salary = [ alloc[:base_salary] + salary_variation, alloc[:base_salary] / 2 ].max

    # Blueprint salary history for this employee
    # History tier: based on tenure cycle
    tenure_tier = current_emp_idx % 3 # 0: 3 salaries, 1: 2 salaries, 2: 1 salary

    salaries = []
    case tenure_tier
    when 0
      # 3 revisions: 2024, 2025, 2026
      salaries << {
        annual_salary: (current_annual_salary * 0.82).round(-2),
        effective_from: Date.new(2024, 1, 1)
      }
      salaries << {
        annual_salary: (current_annual_salary * 0.91).round(-2),
        effective_from: Date.new(2025, 1, 1)
      }
      salaries << {
        annual_salary: current_annual_salary.round(-2),
        effective_from: Date.new(2026, 1, 1)
      }
    when 1
      # 2 revisions: 2025, 2026
      salaries << {
        annual_salary: (current_annual_salary * 0.90).round(-2),
        effective_from: Date.new(2025, 1, 1)
      }
      salaries << {
        annual_salary: current_annual_salary.round(-2),
        effective_from: Date.new(2026, 1, 1)
      }
    else
      # 1 current revision: 2026
      salaries << {
        annual_salary: current_annual_salary.round(-2),
        effective_from: Date.new(2026, 1, 1)
      }
    end

    salary_blueprints << { employee_number: emp_num, salaries: salaries }
    current_emp_idx += 1
  end
end

puts "Inserting/upserting #{employee_records.size} employees in batches..."
employee_records.each_slice(1000) do |slice|
  Employee.upsert_all(slice, unique_by: :employee_number)
end
puts "Employees upsert completed."

# Build map of employee_number to employee_id
puts "Mapping employee IDs..."
emp_id_by_number = Employee.pluck(:employee_number, :id).to_h

salary_records = []
salary_blueprints.each do |blueprint|
  emp_id = emp_id_by_number[blueprint[:employee_number]]
  next unless emp_id

  blueprint[:salaries].each do |s|
    salary_records << {
      employee_id: emp_id,
      annual_salary: s[:annual_salary],
      effective_from: s[:effective_from],
      created_at: now,
      updated_at: now
    }
  end
end

puts "Inserting/upserting #{salary_records.size} salary records in batches..."
salary_records.each_slice(2000) do |slice|
  Salary.upsert_all(slice, unique_by: [ :employee_id, :effective_from ])
end
puts "Salary records upsert completed."

puts "== Seeding complete =="
puts "Total Countries: #{Country.count}"
puts "Total Departments: #{Department.count}"
puts "Total Employees: #{Employee.count}"
puts "Total Salaries: #{Salary.count}"
