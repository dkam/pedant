require "test_helper"

# The push fields of monitors.yml beyond push + interval: durations, values
# with units and limits, start/finish runs, and cron schedules.
class Uptime::PushDefinitionTest < ActiveSupport::TestCase
  setup do
    _token, @digest = push_token
  end

  test "durations can be written as 30s, 5m, 3h or 1d, or plain seconds" do
    monitor = sync("push" => @digest, "interval" => "1d", "grace" => "30m", "max_runtime" => "3h")

    assert_equal [ 86_400, 1800, 10_800 ], [ monitor.interval, monitor.grace, monitor.options["max_runtime"] ]
  end

  test "an unreadable duration is an error" do
    assert_error(/interval/, "push" => @digest, "interval" => "3x")
  end

  test "a value has a label, a unit and optional warn and down limits" do
    monitor = sync("push" => @digest, "interval" => 3600, "value" => { "label" => "Disk used", "unit" => "%", "warn_above" => 80, "down_above" => 90 })

    assert_equal({ "label" => "Disk used", "unit" => "%", "warn_above" => 80, "down_above" => 90 }, monitor.options["value"])
  end

  test "value settings are checked" do
    assert_error(/value.*colour/, "push" => @digest, "interval" => 3600, "value" => { "label" => "Disk", "colour" => "red" })
    assert_error(/down_above.*number/, "push" => @digest, "interval" => 3600, "value" => { "down_above" => "lots" })
    assert_error(/warn_above.*below down_above/, "push" => @digest, "interval" => 3600, "value" => { "warn_above" => 95, "down_above" => 90 })
    assert_error(/warn_below.*above down_below/, "push" => @digest, "interval" => 3600, "value" => { "warn_below" => 5, "down_below" => 10 })
    assert_error(/value.*map/, "push" => @digest, "interval" => 3600, "value" => "87")
  end

  test "a schedule takes the place of an interval, and needs a time zone" do
    monitor = sync("push" => @digest, "schedule" => "0 2 * * 1-5", "timezone" => "Australia/Sydney", "grace" => "30m")

    assert_nil monitor.interval
    assert_equal [ "0 2 * * 1-5", "Australia/Sydney" ], monitor.options.values_at("schedule", "timezone")
  end

  test "schedule entries are checked" do
    assert_error(/schedule needs a timezone/, "push" => @digest, "schedule" => "0 2 * * *")
    assert_error(/schedule/, "push" => @digest, "schedule" => "at two", "timezone" => "Australia/Sydney")
    assert_error(/timezone/, "push" => @digest, "schedule" => "0 2 * * *", "timezone" => "Mars/Olympus")
    assert_error(/interval or a schedule/, "push" => @digest, "interval" => 3600, "schedule" => "0 2 * * *", "timezone" => "UTC")
    assert_error(/interval or a schedule/, "push" => @digest)
    assert_error(/timezone/, "push" => @digest, "interval" => 3600, "timezone" => "UTC")
  end

  test "a new scheduled monitor is first due at the next scheduled time, plus grace" do
    # Saturday 10 October 2026, 7am in Sydney; the next weekday 2am is Monday.
    travel_to Time.utc(2026, 10, 9, 20, 0) do
      monitor = sync("push" => @digest, "schedule" => "0 2 * * 1-5", "timezone" => "Australia/Sydney", "grace" => "30m")

      assert_equal Time.utc(2026, 10, 11, 15, 30), monitor.next_check_at
    end
  end

  test "values, runs and schedules are push settings, not http ones" do
    assert_error(/value/, "http" => "http://splat.local/", "value" => { "unit" => "%" })
    assert_error(/max_runtime/, "http" => "http://splat.local/", "max_runtime" => "1h")
    assert_error(/schedule/, "http" => "http://splat.local/", "schedule" => "0 2 * * *", "timezone" => "UTC")
  end

  private
    def sync(entry)
      source = monitor_source("monitors.yml" => { "job" => entry })
      source.sync!
      assert_empty source.sync_error_list
      source.monitors.sole
    end

    def assert_error(pattern, entry)
      source = monitor_source("monitors.yml" => { "job" => entry })
      source.sync!
      assert_empty source.monitors, "expected #{entry.inspect} to be refused"
      assert_match pattern, source.sync_error_list.join
    end
end
