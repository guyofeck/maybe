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

  test "monthly spending compares calendar months across year boundaries" do
    travel_to Time.zone.local(2026, 1, 15) do
      Entry.where(account: @user.family.accounts).destroy_all
      create_transaction(amount: 100, date: Date.new(2025, 12, 1))
      create_transaction(amount: 100, date: Date.new(2025, 12, 31))
      create_transaction(amount: 300, date: Date.new(2026, 1, 1))
      create_transaction(amount: 999, date: Date.new(2025, 11, 30))
      create_transaction(amount: 999, date: Date.new(2026, 1, 16))
      create_transaction(amount: -500, date: Date.current)
      create_transaction(amount: 500, kind: "funds_movement", date: Date.current)

      get root_path
      assert_response :ok
      assert_select "#monthly-spending dd", text: "$300.00"
      assert_select "#monthly-spending dd", text: "$200.00"
      assert_select "#monthly-spending p", text: /50.0% increase vs. last month/
    end
  end

  test "monthly spending shows a decrease" do
    Entry.where(account: @user.family.accounts).destroy_all
    create_transaction(amount: 200, date: Date.current.prev_month.beginning_of_month)
    create_transaction(amount: 100)

    get root_path
    assert_select "#monthly-spending p", text: /50.0% decrease vs. last month/
  end

  test "monthly spending handles no previous spending" do
    Entry.where(account: @user.family.accounts).destroy_all
    get root_path
    assert_select "#monthly-spending p", text: /0.0% change vs. last month/

    create_transaction(amount: 100)
    get root_path
    assert_select "#monthly-spending p", text: "Percentage change unavailable — no spending last month"
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
