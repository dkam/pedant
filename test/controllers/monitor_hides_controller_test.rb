require "test_helper"

# Hiding a down monitor from its page (dkam/pedant#17, ADR 0033).
class MonitorHidesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
    _token, digest = push_token
    monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "kith" => { "name" => "Kith", "http" => "http://splat.local:3040/up", "retries" => 0 },
      "tuber" => { "name" => "Tuber", "http" => "http://splat.local:3050/up" },
      "backup" => { "name" => "pg02 backup", "push" => digest, "interval" => "26h" }
    }).sync!
    @splat = monitor("splat")
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    monitor("kith").record(Uptime::Result.new(status: "down", message: "HTTP 502"))
    monitor("tuber").record(Uptime::Result.new(status: "up"))
    @backup = monitor("backup")
    @backup.record_push(@backup.push_result(status: "down", message: "backup of booko_production.dump failed"))
  end

  test "hiding needs a login" do
    post monitor_hide_url(@splat), params: { until: "day" }

    assert_redirected_to login_url
    assert_not @splat.reload.hidden?
  end

  test "a down push monitor's page offers to hide it until its next run, or for 24 hours" do
    sign_in_with_password

    get monitor_url(@backup)

    assert_select "[data-hide] form[action=?]", monitor_hide_path(@backup), 2
    assert_select "[data-hide] input[name=until][value=next_run]"
    assert_select "[data-hide] input[name=until][value=day]"
  end

  test "a down active check can be hidden for 24 hours only, and an up one not at all" do
    sign_in_with_password

    get monitor_url(@splat)
    assert_select "[data-hide] input[name=until]", 1
    assert_select "[data-hide] input[name=until][value=day]"

    get monitor_url(monitor("tuber"))
    assert_select "[data-hide]", 0
  end

  test "hiding until its next run says when it ends, and it can be shown again" do
    sign_in_with_password

    post monitor_hide_url(@backup), params: { until: "next_run" }
    assert_redirected_to monitor_url(@backup)
    assert @backup.reload.hidden?
    assert @backup.hidden_until_next_push

    follow_redirect!
    assert_select "[data-hide]", /Hidden for 1 day more, or until its next push/

    delete monitor_hide_url(@backup)
    assert_redirected_to monitor_url(@backup)
    assert_not @backup.reload.hidden?
  end

  test "an up monitor can't be hidden" do
    sign_in_with_password
    tuber = monitor("tuber")

    post monitor_hide_url(tuber), params: { until: "day" }

    assert_redirected_to monitor_url(tuber)
    assert_equal "Only a down monitor can be hidden.", flash[:alert]
    assert_not tuber.reload.hidden?
  end

  test "on the dashboard a hidden monitor is muted, below the ones still down, and counted apart" do
    sign_in_with_password
    @splat.hide!

    get root_url

    assert_equal %w[ kith backup splat tuber ], css_select("[data-monitor]").map { |row| row["data-monitor"] }
    assert_select "[data-monitor=splat] [data-state=hidden]"
    assert_select "[data-monitor=splat] .text-bad", 0
    assert_select "h1 + p", /2 down · 1 hidden · 1 up/
  end

  private
    def monitor(key) = Uptime::Monitor.find_by!(key: key)
end
