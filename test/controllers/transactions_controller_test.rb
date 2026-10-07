require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntryableResourceInterfaceTest, EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
  end

  test "downloads all filtered transactions regardless of pagination" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "CSV account", balance: 0, currency: "USD", accountable: Depository.new
    category = family.categories.create! name: "Food", color: "#ff0000"
    older = create_transaction(account: account, name: 'CSV match, "older"', category: category, date: Date.current - 1.day, amount: -12.50, notes: "Line one\nLine two")
    newer = create_transaction(account: account, name: "CSV match newer", category: category, date: Date.current, amount: 25)
    create_transaction(account: account, name: "Not matched", category: category)
    create_transaction(name: "CSV match other family", category: categories(:food_and_drink))

    get transactions_url(format: :csv, q: { search: "CSV match", categories: [ "Food" ] }, page: 2, per_page: 1)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "transactions-#{Date.current.iso8601}.csv"
    rows = CSV.parse(response.body, headers: true)
    assert_equal [ newer.name, older.name ], rows.map { |row| row["name"] }
    assert_equal "-12.5", rows[1]["amount"]
    assert_equal older.notes, rows[1]["notes"]
    assert_equal "CSV account", rows[1]["account_name"]
    assert_equal "Food", rows[1]["category"]
    assert_equal "USD", rows[1]["currency"]
  end

  test "empty CSV export contains headers and does not change saved page filters" do
    get transactions_url(q: { search: "Saved filter" }, per_page: 10)
    session = @user.sessions.order(:created_at).last
    saved_params = session.prev_transaction_page_params

    get transactions_url(format: :csv, q: { search: "No matching CSV transactions" })

    assert_response :success
    csv = CSV.parse(response.body, headers: true)
    assert_empty csv
    assert_equal %w[date account_name amount name category tags notes currency], csv.headers
    assert_equal saved_params, session.reload.prev_transaction_page_params
  end

  test "CSV export protects spreadsheet formulas in text fields" do
    entry = create_transaction(name: "=SUM(1,2)", notes: "+formula")

    get transactions_url(format: :csv, q: { search: entry.name })

    assert_response :success
    row = CSV.parse(response.body, headers: true).first
    assert_equal "'=SUM(1,2)", row["name"]
    assert_equal "'+formula", row["notes"]
  end

  test "download link preserves the current filters" do
    get transactions_url(q: { search: "Coffee", types: [ "expense" ] })

    assert_select "a[data-turbo='false']", text: "Download CSV" do |links|
      assert_equal transactions_path(format: :csv, q: { search: "Coffee", types: [ "expense" ] }), links.first["href"]
    end
  end

  test "creates with transaction details" do
    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      post transactions_url, params: {
        entry: {
          account_id: @entry.account_id,
          name: "New transaction",
          date: Date.current,
          currency: "USD",
          amount: 100,
          nature: "inflow",
          entryable_type: @entry.entryable_type,
          entryable_attributes: {
            tag_ids: [ Tag.first.id, Tag.second.id ],
            category_id: Category.first.id,
            merchant_id: Merchant.first.id
          }
        }
      }
    end

    created_entry = Entry.order(:created_at).last

    assert_redirected_to account_url(created_entry.account)
    assert_equal "Transaction created", flash[:notice]
    assert_enqueued_with(job: SyncJob)
  end

  test "updates with transaction details" do
    assert_no_difference [ "Entry.count", "Transaction.count" ] do
      patch transaction_url(@entry), params: {
        entry: {
          name: "Updated name",
          date: Date.current,
          currency: "USD",
          amount: 100,
          nature: "inflow",
          entryable_type: @entry.entryable_type,
          notes: "test notes",
          excluded: false,
          entryable_attributes: {
            id: @entry.entryable_id,
            tag_ids: [ Tag.first.id, Tag.second.id ],
            category_id: Category.first.id,
            merchant_id: Merchant.first.id
          }
        }
      }
    end

    @entry.reload

    assert_equal "Updated name", @entry.name
    assert_equal Date.current, @entry.date
    assert_equal "USD", @entry.currency
    assert_equal -100, @entry.amount
    assert_equal [ Tag.first.id, Tag.second.id ], @entry.entryable.tag_ids.sort
    assert_equal Category.first.id, @entry.entryable.category_id
    assert_equal Merchant.first.id, @entry.entryable.merchant_id
    assert_equal "test notes", @entry.notes
    assert_equal false, @entry.excluded

    assert_equal "Transaction updated", flash[:notice]
    assert_redirected_to account_url(@entry.account)
    assert_enqueued_with(job: SyncJob)
  end

  test "transaction count represents filtered total" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

    3.times do
      create_transaction(account: account)
    end

    get transactions_url(per_page: 10)

    assert_dom "#total-transactions", count: 1, text: family.entries.transactions.size.to_s

    searchable_transaction = create_transaction(account: account, name: "Unique test name")

    get transactions_url(q: { search: searchable_transaction.name })

    # Only finds 1 transaction that matches filter
    assert_dom "#" + dom_id(searchable_transaction), count: 1
    assert_dom "#total-transactions", count: 1, text: "1"
  end

  test "can paginate" do
  family = families(:empty)
  sign_in users(:empty)

  # Clean up any existing entries to ensure clean test
  family.accounts.each { |account| account.entries.delete_all }

  account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

  # Create multiple transactions for pagination
  25.times do |i|
    create_transaction(
      account: account,
      name: "Transaction #{i + 1}",
      amount: 100 + i,  # Different amounts to prevent transfer matching
      date: Date.current - i.days  # Different dates
    )
  end

  total_transactions = family.entries.transactions.count
  assert_operator total_transactions, :>=, 20, "Should have at least 20 transactions for testing"

  # Test page 1 - should show limited transactions
  get transactions_url(page: 1, per_page: 10)
  assert_response :success

  page_1_count = css_select("turbo-frame[id^='entry_']").count
  assert_equal 10, page_1_count, "Page 1 should respect per_page limit"

  # Test page 2 - should show different transactions
  get transactions_url(page: 2, per_page: 10)
  assert_response :success

  page_2_count = css_select("turbo-frame[id^='entry_']").count
  assert_operator page_2_count, :>, 0, "Page 2 should show some transactions"
  assert_operator page_2_count, :<=, 10, "Page 2 should not exceed per_page limit"

  # Test Pagy overflow handling - should redirect or handle gracefully
  get transactions_url(page: 9999999, per_page: 10)

  # Either success (if Pagy shows last page) or redirect (if Pagy redirects)
  assert_includes [ 200, 302 ], response.status, "Pagy should handle overflow gracefully"

  if response.status == 302
    follow_redirect!
    assert_response :success
  end

  overflow_count = css_select("turbo-frame[id^='entry_']").count
  assert_operator overflow_count, :>, 0, "Overflow should show some transactions"
end

  test "calls Transaction::Search totals method with correct search parameters" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

    create_transaction(account: account, amount: 100)

    search = Transaction::Search.new(family)
    totals = OpenStruct.new(
      count: 1,
      expense_money: Money.new(10000, "USD"),
      income_money: Money.new(0, "USD")
    )

    Transaction::Search.expects(:new).with(family, filters: {}).returns(search)
    search.expects(:totals).once.returns(totals)

    get transactions_url
    assert_response :success
  end

  test "calls Transaction::Search totals method with filtered search parameters" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new
    category = family.categories.create! name: "Food", color: "#ff0000"

    create_transaction(account: account, amount: 100, category: category)

    search = Transaction::Search.new(family, filters: { "categories" => [ "Food" ], "types" => [ "expense" ] })
    totals = OpenStruct.new(
      count: 1,
      expense_money: Money.new(10000, "USD"),
      income_money: Money.new(0, "USD")
    )

    Transaction::Search.expects(:new).with(family, filters: { "categories" => [ "Food" ], "types" => [ "expense" ] }).returns(search)
    search.expects(:totals).once.returns(totals)

    get transactions_url(q: { categories: [ "Food" ], types: [ "expense" ] })
    assert_response :success
  end
end
