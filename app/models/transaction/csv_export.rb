require "csv"

class Transaction::CsvExport
  def initialize(transactions)
    @transactions = transactions
  end

  def generate
    CSV.generate do |csv|
      csv << [ "Date", "Name", "Account", "Amount", "Currency", "Category", "Merchant", "Tags", "Notes" ]

      @transactions.to_a.uniq(&:id).each do |transaction|
        entry = transaction.entry
        csv << [
          entry.date.iso8601,
          safe_text(entry.name),
          safe_text(entry.account.name),
          entry.amount.to_s("F"),
          entry.currency,
          safe_text(transaction.category&.name),
          safe_text(transaction.merchant&.name),
          safe_text(transaction.tags.map(&:name).sort.join(", ")),
          safe_text(entry.notes)
        ]
      end
    end
  end

  private
    # Prevent user-entered text from being interpreted as spreadsheet formulas.
    def safe_text(value)
      value.to_s.match?(/\A[=+\-@\t\r\n]/) ? "'#{value}" : value
    end
end
