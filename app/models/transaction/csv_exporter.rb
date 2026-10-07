require "csv"

class Transaction::CsvExporter
  def initialize(transactions)
    @transactions = transactions
  end

  def generate
    CSV.generate do |csv|
      csv << %w[date account_name amount name category tags notes currency]

      @transactions.each do |transaction|
        entry = transaction.entry
        csv << [
          entry.date.iso8601,
          safe_text(entry.account.name),
          entry.amount.to_s("F"),
          safe_text(entry.name),
          safe_text(transaction.category&.name),
          safe_text(transaction.tags.map(&:name).join(",")),
          safe_text(entry.notes),
          entry.currency
        ]
      end
    end
  end

  private
    # Prevent user-entered text from becoming a formula when opened in a spreadsheet.
    def safe_text(value)
      value.to_s.match?(/\A[\s]*[=+\-@]/) ? "'#{value}" : value
    end
end
