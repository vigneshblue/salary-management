# Centralized currency conversion service for illustrative dashboard reporting.
#
# NOTE: Exchange rates are illustrative reporting rates based on INR,
# not live market rates.
class CurrencyConverter
  SUPPORTED_CURRENCIES = %w[INR USD GBP CAD AUD].freeze
  DEFAULT_CURRENCY = "INR".freeze

  # Illustrative exchange rates relative to INR (1 Unit of Currency = X INR)
  # Standard indicative reporting benchmark:
  # 1 USD = 83.00 INR
  # 1 GBP = 105.00 INR
  # 1 EUR = 90.00 INR (optional fallback if needed)
  # 1 CAD = 61.00 INR
  # 1 AUD = 54.00 INR
  # 1 INR = 1.00 INR
  RATES_TO_INR = {
    "INR" => BigDecimal("1.0"),
    "USD" => BigDecimal("83.0"),
    "GBP" => BigDecimal("105.0"),
    "CAD" => BigDecimal("61.0"),
    "AUD" => BigDecimal("54.0")
  }.freeze

  class << self
    def normalize_currency(currency)
      curr = currency.to_s.upcase.strip
      SUPPORTED_CURRENCIES.include?(curr) ? curr : DEFAULT_CURRENCY
    end

    def convert(amount, from:, to:)
      return BigDecimal("0.00") if amount.blank?

      amount_d = BigDecimal(amount.to_s)
      from_curr = normalize_currency(from)
      to_curr = normalize_currency(to)

      return amount_d.round(2, :half_up) if from_curr == to_curr

      rate_from = RATES_TO_INR[from_curr] || BigDecimal("1.0")
      rate_to = RATES_TO_INR[to_curr] || BigDecimal("1.0")

      # Convert from `from_curr` to INR, then from INR to `to_curr`
      # amount_in_inr = amount_d * rate_from
      # amount_in_to = amount_in_inr / rate_to
      amount_in_inr = amount_d * rate_from
      converted = amount_in_inr / rate_to

      converted.round(2, :half_up)
    end
  end
end
