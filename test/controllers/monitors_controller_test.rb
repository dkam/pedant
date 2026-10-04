require "test_helper"

class MonitorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "kith" => { "name" => "Kith", "http" => "http://splat.local:3040/up" },
      "gone" => { "name" => "Gone", "http" => "http://splat.local:3050/up" }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @source.monitors.find_by!(key: "gone").update!(retired_at: Time.current)
  end

  test "the dashboard needs a login" do
    get root_url

    assert_redirected_to login_url
  end

  test "the dashboard lists active monitors with their state, down first" do
    sign_in_with_password
    get root_url

    assert_response :success
    assert_select "[data-monitor]", 2
    assert_select "[data-monitor]:first-of-type", /Splat/
    assert_select "[data-monitor=splat] [data-state=down]"
    assert_select "[data-monitor=splat]", /HTTP 503/
    assert_select "[data-monitor=kith] [data-state=pending]"
    assert_select "[data-monitor=gone]", 0
  end

  test "a source's sync errors show on the dashboard" do
    write_monitor_files(@source.path, "monitors.yml" => "nope: [")
    @source.sync!
    sign_in_with_password

    get root_url

    assert_select ".alert", /monitors.yml/
  end

  test "with no sources yet, the dashboard says where to add one" do
    Uptime::Check.delete_all
    Uptime::StateChange.delete_all
    Uptime::Monitor.delete_all
    Uptime::Source.delete_all
    sign_in_with_password

    get root_url

    assert_select "a[href=?]", settings_path
  end

  test "a monitor's page shows its recent checks and state changes" do
    sign_in_with_password

    get monitor_url(@splat)

    assert_response :success
    assert_select "h1", /Splat/
    assert_select "[data-check]", 1
    assert_select "[data-state-change]", 1
    assert_includes response.body, "monitors.yml"
  end
end
