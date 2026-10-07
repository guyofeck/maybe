require "csv"

class Transaction::CsvExport
  def initialize(transactions)
    @transactions = transactions
  end

  def generate
    CSV.generate(headers: true) do |csv|
      csv << [ "Date", "Name", "Account", "Category", "Merchant", "Tags", "Amount", "Currency", "Notes" ]

      @transactions.to_a.uniq(&:id).each do |transaction|
        entry = transaction.entry
        csv << [
          entry.date.iso8601,
          safe_text(entry.name),
          safe_text(entry.account.name),
          safe_text(transaction.category&.name),
          safe_text(transaction.merchant&.name),
          safe_text(transaction.tags.map(&:name).join(", ")),
          (-entry.amount).to_s("F"),
          entry.currency,
          safe_text(entry.notes)
        ]
      end
    end
  end

  private
    # Prevent user-entered text from being interpreted as spreadsheet formulas.
    def safe_text(value)
      text = value.to_s
      text.match?(/\A[\s]*[=+\-@]/) ? "'#{text}" : text
    end
end
