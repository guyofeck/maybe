require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper
  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
  end

  test "monthly spending compares month to date with the full previous calendar month" do
    travel_to Date.new(2026, 1, 15) do
      Entry.joins(:account).where(accounts: { family_id: @user.family.id }).destroy_all
      account = @user.family.accounts.first
      create_transaction(account: account, amount: 100, date: Date.new(2025, 12, 1))
      create_transaction(account: account, amount: 100, date: Date.new(2025, 12, 31))
      create_transaction(account: account, amount: 50, date: Date.new(2026, 1, 1))
      create_transaction(account: account, amount: 50, date: Date.current)
      create_transaction(account: account, amount: 999, date: Date.new(2025, 11, 30))
      create_transaction(account: account, amount: 999, date: Date.new(2026, 1, 16))
      create_transaction(account: account, amount: -500, date: Date.current)
      create_transaction(account: account, amount: 500, date: Date.current, kind: "funds_movement")
      create_transaction(account: account, amount: 500, date: Date.current).update!(excluded: true)

      get root_path, params: { cashflow_period: "last_365_days" }

      assert_response :ok
      assert_select "#monthly-spending [data-testid=current-month-spending]", text: "$100.00"
      assert_select "#monthly-spending [data-testid=previous-month-spending]", text: "$200.00"
      assert_select "#monthly-spending [data-testid=spending-change]", text: /-50.0%/
    end
  end

  test "monthly spending handles increases unchanged totals and zero previous spending" do
    travel_to Date.new(2026, 1, 15) do
      [ [ 150, 100, "50.0%" ], [ 100, 100, "0.0%" ], [ 0, 0, "0.0%" ],
        [ 100, 0, "Percentage unavailable" ], [ 0, 100, "-100.0%" ] ].each do |current, previous, expected|
        Entry.joins(:account).where(accounts: { family_id: @user.family.id }).destroy_all
        account = @user.family.accounts.first
        create_transaction(account: account, amount: current, date: Date.current) unless current.zero?
        create_transaction(account: account, amount: previous, date: Date.new(2025, 12, 31)) unless previous.zero?

        get root_path

        assert_response :ok
        assert_select "#monthly-spending [data-testid=spending-change]", text: /#{Regexp.escape(expected)}/
      end
    end
  end

  test "changelog" do
    VCR.use_cassette("git_repository_provider/fetch_latest_release_notes") do
      get changelog_path
      assert_response :ok
    end
  end

  test "changelog with nil release notes" do
    # Mock the GitHub provider to return nil (simulating API failure or no releases)
    github_provider = mock
    github_provider.expects(:fetch_latest_release_notes).returns(nil)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Release notes unavailable"
    assert_select "a[href='https://github.com/maybe-finance/maybe/releases']"
  end

  test "changelog with incomplete release notes" do
    # Mock the GitHub provider to return incomplete data (missing some fields)
    github_provider = mock
    incomplete_data = {
      avatar: nil,
      username: "maybe-finance",
      name: "Test Release",
      published_at: nil,
      body: nil
    }
    github_provider.expects(:fetch_latest_release_notes).returns(incomplete_data)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Test Release"
    # Should not crash even with nil values
  end
end
