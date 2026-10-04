require "test_helper"

# What a push can carry beyond up or down: a value, judged against the limits
# in monitors.yml, and the start of a run, so its duration is known and a
# hung run is noticed.
class PushValuesAndRunsTest < ActionDispatch::IntegrationTest
  setup do
    PushesController::RATE_LIMITS.clear
    @token, @digest = push_token
  end

  test "a value within its limits is up, and kept with the check" do
    monitor = disk_monitor

    get push_url_for(value: "50")

    monitor.reload
    assert_equal "up", monitor.state
    assert_equal 50.0, monitor.last_value
    assert_equal 50.0, monitor.checks.sole.value
  end

  test "a value past its warn limit is warn, saying what and by how much" do
    monitor = disk_monitor

    get push_url_for(value: "85")

    monitor.reload
    assert_equal "warn", monitor.state
    assert_equal "Disk used 85% (over 80%)", monitor.last_message
  end

  test "a value past its down limit is down" do
    monitor = disk_monitor

    get push_url_for(value: "93.5")

    monitor.reload
    assert_equal "down", monitor.state
    assert_equal "Disk used 93.5% (over 90%)", monitor.last_message
  end

  test "limits can be lower bounds too" do
    monitor = sync("push" => @digest, "interval" => 3600, "value" => { "label" => "Free space", "unit" => "GB", "warn_below" => 50, "down_below" => 10 })

    get push_url_for(value: "8")

    assert_equal "Free space 8 GB (under 10 GB)", monitor.reload.last_message
  end

  test "the job's own down wins over a value within limits, and its message is kept" do
    monitor = disk_monitor

    get push_url_for(status: "down", value: "50", msg: "fsck failed")

    monitor.reload
    assert_equal "down", monitor.state
    assert_equal "fsck failed", monitor.last_message
  end

  test "a value that isn't a number is down, since the script is broken" do
    monitor = disk_monitor

    get push_url_for(value: "lots")

    monitor.reload
    assert_equal "down", monitor.state
    assert_match(/isn't a number/, monitor.last_message)
  end

  test "a value with no limits is only recorded" do
    monitor = sync("push" => @digest, "interval" => 3600, "value" => { "label" => "Rows copied" })

    get push_url_for(value: "1200000")

    assert_equal [ "up", 1_200_000.0 ], monitor.reload.values_at(:state, :last_value)
  end

  test "ping still means milliseconds, for scripts moved from Kuma" do
    monitor = sync("push" => @digest, "interval" => 3600)

    get push_url_for(ping: "42")

    assert_equal 42, monitor.checks.sole.latency_ms
  end

  test "status=start records the start and changes nothing else" do
    monitor = sync("push" => @digest, "interval" => 3600)
    monitor.record_push(Uptime::Result.new(status: "up"))

    freeze_time do
      get push_url_for(status: "start")

      assert_response :success
      monitor.reload
      assert_equal Time.current, monitor.started_at
      assert_equal "up", monitor.state
      assert_equal 1, monitor.checks.count
    end
  end

  test "the finish records how long the run took" do
    monitor = sync("push" => @digest, "interval" => 3600)

    get push_url_for(status: "start")
    travel 12.minutes
    get push_url_for(status: "up")

    monitor.reload
    assert_nil monitor.started_at
    assert_in_delta 12.minutes.in_milliseconds, monitor.checks.sole.duration_ms, 1000
  end

  test "a run that outlasts max_runtime is down long before the interval runs out" do
    monitor = sync("push" => @digest, "interval" => "1d", "max_runtime" => "1h")
    monitor.record_push(Uptime::Result.new(status: "up"))

    get push_url_for(status: "start")
    assert_equal 1.hour.from_now.to_i, monitor.reload.next_check_at.to_i

    travel 61.minutes
    Uptime::Clock.tick!(15.seconds.ago)
    perform_enqueued_jobs { Uptime::ScheduleChecksJob.perform_now }

    monitor.reload
    assert_equal "down", monitor.state
    assert_equal "Started 1 hour and 1 minute ago, still running", monitor.last_message
  end

  test "without max_runtime, a start doesn't bring the deadline forward" do
    monitor = sync("push" => @digest, "interval" => "1d")
    monitor.record_push(Uptime::Result.new(status: "up"))
    due = monitor.reload.next_check_at

    get push_url_for(status: "start")

    assert_equal due, monitor.reload.next_check_at
  end

  private
    def disk_monitor
      sync("push" => @digest, "interval" => 3600, "value" => { "label" => "Disk used", "unit" => "%", "warn_above" => 80, "down_above" => 90 })
    end

    def sync(entry)
      source = monitor_source("monitors.yml" => { "job" => entry })
      source.sync!
      assert_empty source.sync_error_list
      source.monitors.sole
    end

    def push_url_for(**params)
      "/api/push/#{@token}?#{params.to_query}"
    end
end
