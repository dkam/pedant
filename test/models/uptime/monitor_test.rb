require "test_helper"

# The liveness model (#5): a state, read as "did it change, and how often does
# it flap".
class Uptime::MonitorTest < ActiveSupport::TestCase
  setup do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up", "retries" => 1 } })
    source.sync!
    @monitor = source.monitors.sole
  end

  test "a new monitor is pending until its first result" do
    assert_equal "pending", @monitor.state

    @monitor.record(result("up"))

    assert_equal "up", @monitor.state
    assert_equal [ [ "pending", "up" ] ], @monitor.state_changes.pluck(:from_state, :to_state)
  end

  test "every result is kept as a check" do
    @monitor.record(result("up", latency_ms: 42))
    @monitor.record(result("down", message: "HTTP 503"))

    assert_equal [ [ "up", 42, nil ], [ "down", nil, "HTTP 503" ] ], @monitor.checks.order(:id).pluck(:status, :latency_ms, :message)
    assert_equal "HTTP 503", @monitor.last_message
  end

  test "failures up to the retry count don't make it down" do
    @monitor.record(result("up"))

    @monitor.record(result("down", message: "HTTP 503"))

    assert_equal "up", @monitor.state
    assert_equal 1, @monitor.consecutive_failures
    assert @monitor.retrying?
  end

  test "one failure past the retry count makes it down, recording why and when" do
    @monitor.record(result("up"))

    freeze_time do
      2.times { @monitor.record(result("down", message: "HTTP 503")) }

      assert_equal "down", @monitor.state
      assert_equal Time.current, @monitor.state_changed_at
      assert_equal [ "up", "down", "HTTP 503" ], @monitor.state_changes.last.values_at(:from_state, :to_state, :message)
    end
  end

  test "a monitor that has never been up still goes down after its retries" do
    2.times { @monitor.record(result("down", message: "Connection refused")) }

    assert_equal "down", @monitor.state
  end

  test "one success recovers it and clears the failure count" do
    2.times { @monitor.record(result("down")) }

    @monitor.record(result("up"))

    assert_equal "up", @monitor.state
    assert_equal 0, @monitor.consecutive_failures
  end

  test "unknown is its own state, and doesn't count as a failure" do
    @monitor.record(result("up"))
    @monitor.record(result("down"))

    @monitor.record(result("unknown", message: "Pedant is offline"))

    assert_equal "unknown", @monitor.state
    assert_equal 1, @monitor.consecutive_failures
  end

  test "flaps count how often it went down in the window" do
    travel_to 2.days.ago do
      @monitor.record(result("down"))
      @monitor.record(result("down"))
      @monitor.record(result("up"))
    end
    3.times do
      2.times { @monitor.record(result("down")) }
      @monitor.record(result("up"))
    end

    assert_equal 3, @monitor.flaps(within: 24.hours)
    assert_equal 4, @monitor.flaps(within: 3.days)
  end

  test "each result schedules the next check one interval on" do
    freeze_time do
      @monitor.record(result("up"))

      assert_equal Time.current, @monitor.last_checked_at
      assert_equal 60.seconds.from_now, @monitor.next_check_at
    end
  end

  test "old checks are pruned and state changes are kept" do
    travel_to 15.days.ago do
      2.times { @monitor.record(result("down")) }
    end
    @monitor.record(result("up"))

    Uptime::Check.prune

    assert_equal 1, @monitor.checks.count
    assert_equal 2, @monitor.state_changes.count
  end

  test "warn is its own state: not a failure, and not a flap" do
    @monitor.record(result("down"))

    @monitor.record(result("warn", message: "Disk used 85% (over 80%)"))

    assert_equal [ "warn", 0, 0 ], [ @monitor.state, @monitor.consecutive_failures, @monitor.flaps ]
  end

  test "the dashboard order puts warn after down and unknown, before pending and up" do
    states = %w[ up pending warn unknown down ]
    source = monitor_source("monitors.yml" => states.to_h { |state| [ state, { "http" => "http://#{state}.local/" } ] })
    source.sync!
    source.monitors.each { |monitor| monitor.update_columns(state: monitor.key) }

    assert_equal %w[ down unknown warn pending up ], source.monitors.by_urgency.pluck(:state)
  end

  # Two scheduler runs that load the same due monitor mustn't both queue it.
  test "a due monitor can be claimed for a check only once" do
    first = Uptime::Monitor.find(@monitor.id)
    second = Uptime::Monitor.find(@monitor.id)

    assert first.claim_for_check
    assert_not second.claim_for_check
  end

  test "a claim lasts the timeout plus a lease, so a lost check is retried" do
    freeze_time do
      @monitor.claim_for_check

      assert_equal (10 + 60).seconds.from_now, @monitor.reload.next_check_at
    end
  end

  private
    def result(status, latency_ms: nil, message: nil)
      Uptime::Result.new(status: status, latency_ms: latency_ms, message: message)
    end
end
