require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
  end

  test "dashboard compares month to date spending with the full previous month" do
    travel_to Time.zone.local(2026, 1, 15) do
      @user.family.entries.update_all(excluded: true)
      create_spending_entry(date: Date.new(2026, 1, 1), amount: 150)
      create_spending_entry(date: Date.new(2026, 1, 15), amount: 150)
      create_spending_entry(date: Date.new(2025, 12, 1), amount: 100)
      create_spending_entry(date: Date.new(2025, 12, 31), amount: 100)
      create_spending_entry(date: Date.new(2025, 11, 30), amount: 999)
      create_spending_entry(date: Date.new(2026, 1, 16), amount: 999)
      create_spending_entry(date: Date.current, amount: -1000)
      create_spending_entry(date: Date.current, amount: 999, kind: "funds_movement")
      create_spending_entry(date: Date.current, amount: 999, excluded: true)

      get root_path, params: { cashflow_period: "last_365_days" }

      assert_response :ok
      assert_select "#spending-comparison [data-current-spending]", text: "$300.00"
      assert_select "#spending-comparison [data-previous-spending]", text: "$200.00"
      assert_select "#spending-comparison [data-spending-change]", text: /50.0% more spending/
    end
  end

  test "dashboard shows a spending decrease" do
    travel_to Time.zone.local(2026, 1, 15) do
      @user.family.entries.update_all(excluded: true)
      create_spending_entry(date: Date.current, amount: 100)
      create_spending_entry(date: Date.new(2025, 12, 31), amount: 200)

      get root_path

      assert_response :ok
      assert_select "#spending-comparison [data-spending-change]", text: /50.0% less spending/
    end
  end

  test "dashboard handles no previous month spending" do
    travel_to Time.zone.local(2026, 1, 15) do
      @user.family.entries.update_all(excluded: true)
      create_spending_entry(date: Date.current, amount: 100)

      get root_path

      assert_response :ok
      assert_select "#spending-comparison [data-previous-spending]", text: "$0.00"
      assert_select "#spending-comparison [data-spending-change]", text: /Percentage change unavailable/
    end
  end

  test "dashboard handles no spending in either month" do
    travel_to Time.zone.local(2026, 1, 15) do
      @user.family.entries.update_all(excluded: true)

      get root_path

      assert_response :ok
      assert_select "#spending-comparison [data-current-spending]", text: "$0.00"
      assert_select "#spending-comparison [data-previous-spending]", text: "$0.00"
      assert_select "#spending-comparison [data-spending-change]", text: "0.0% change vs. last month"
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

  private
    def create_spending_entry(date:, amount:, kind: "standard", excluded: false)
      accounts(:depository).entries.create!(
        name: "Spending comparison test",
        date: date,
        amount: amount,
        currency: "USD",
        excluded: excluded,
        entryable: Transaction.new(kind: kind)
      )
    end
end
