require "csv"

class Transaction::CsvExporter
  def initialize(transactions)
    @transactions = transactions
  end

  def generate
    CSV.generate do |csv|
      csv << [ "date", "account_name", "amount", "name", "category", "tags", "notes", "currency" ]

      @transactions.each do |transaction|
        entry = transaction.entry
        csv << [
          entry.date.iso8601,
          entry.account.name,
          entry.amount.to_s,
          entry.name,
          transaction.category&.name,
          transaction.tags.map(&:name).join(","),
          entry.notes,
          entry.currency
        ]
      end
    end
  end
end
