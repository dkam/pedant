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
    AlertDelivery.delete_all
    Alert.delete_all
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

  test "a push monitor shows when it last pushed and how to push, never a token" do
    token, digest = push_token
    monitor = monitor_source({ "monitors.yml" => { "nas-backup" => { "name" => "NAS backup", "push" => digest, "interval" => 86_400 } } }, "other").tap(&:sync!).monitors.sole
    monitor.record_push(Uptime::Result.new(status: "up"))
    sign_in_with_password

    get root_url
    assert_select "[data-monitor=nas-backup]", /Push, expected every 1 day \(last less than a minute ago\)/

    get monitor_url(monitor)
    assert_includes response.body, "/api/push/&lt;token&gt;"
    assert_not_includes response.body, token
  end

  test "a monitor's page graphs its values in their own unit, its run times, or its latency" do
    _token, digest = push_token
    disk = monitor_source({ "monitors.yml" => {
      "disk" => { "push" => digest, "interval" => 3600, "value" => { "label" => "Disk used", "unit" => "%" } }
    } }, "other").tap(&:sync!).monitors.sole
    [ 40, 55, 61 ].each { |value| disk.record_push(Uptime::Result.new(status: "up", value: value, duration_ms: value * 1000)) }
    [ 12, 30 ].each { |ms| @splat.record(Uptime::Result.new(status: "up", latency_ms: ms)) }
    sign_in_with_password

    get monitor_url(disk)
    assert_select "[data-chart=value]", /Disk used \(%\)/
    assert_select "[data-chart=value] svg polyline"
    assert_select "[data-chart=value]", /61/
    assert_select "[data-chart=duration]", /Run time/

    get monitor_url(@splat)
    assert_select "[data-chart=latency]", /Latency \(ms\)/
    assert_select "[data-chart=value]", 0
  end
end
