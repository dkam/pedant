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

  test "free space heading for zero within down_within is down, saying when" do
    monitor = free_space_monitor
    history monitor, hours: 24 do |hours_ago| 40 + hours_ago end # 1 GB an hour

    get push_url_for(value: "40")

    monitor.reload
    assert_equal "down", monitor.state
    assert_equal "Free on / 40 GB, reaches 0 GB in about 2 days", monitor.last_message
  end

  test "heading for zero within warn_within is warn" do
    monitor = free_space_monitor
    history monitor, hours: 24 do |hours_ago| 200 + hours_ago end

    get push_url_for(value: "200")

    monitor.reload
    assert_equal "warn", monitor.state
    assert_equal "Free on / 200 GB, reaches 0 GB in about 8 days", monitor.last_message
  end

  test "a down limit wins over a forecast's warn, and a forecast's down over a warn limit" do
    monitor = sync("push" => @digest, "interval" => 300, "value" => { "label" => "Free on /", "unit" => "GB",
      "down_below" => 5, "warn_below" => 100, "forecast" => { "reaches" => 0, "down_within" => "3d", "warn_within" => "14d" } })
    history monitor, hours: 24 do |hours_ago| 4 + hours_ago * 0.01 end

    get push_url_for(value: "4")
    assert_equal "Free on / 4 GB (under 5 GB)", monitor.reload.last_message

    monitor.checks.delete_all
    history monitor, hours: 24 do |hours_ago| 50 + hours_ago end
    get push_url_for(value: "50")
    assert_equal [ "down", "Free on / 50 GB, reaches 0 GB in about 2 days" ], monitor.reload.values_at(:state, :last_message)
  end

  test "steady free space is up, and a new monitor has no forecast yet" do
    monitor = free_space_monitor

    get push_url_for(value: "40")
    assert_equal "up", monitor.reload.state

    history monitor, hours: 24 do 40 end
    get push_url_for(value: "40")
    assert_equal "up", monitor.reload.state
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

    def free_space_monitor
      sync("push" => @digest, "interval" => 300, "value" => { "label" => "Free on /", "unit" => "GB",
        "forecast" => { "reaches" => 0, "down_within" => "3d", "warn_within" => "14d" } })
    end

    # Pushed values every 5 minutes, up to 5 minutes ago. The block gets whole
    # hours ago.
    def history(monitor, hours:)
      now = Time.current
      (hours * 12).downto(1).each do |step|
        monitor.checks.create!(status: "up", value: yield((step * 5) / 60), checked_at: now - (step * 5).minutes)
      end
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
