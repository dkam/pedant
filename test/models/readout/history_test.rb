require "test_helper"

class Readout::HistoryTest < ActiveSupport::TestCase
  setup do
    _token, digest = push_token
    @source = monitor_source("monitors.yml" => {
      "splat" => { "http" => "http://splat.local:3030/up", "retries" => 0 },
      "nas-backup" => { "push" => digest, "interval" => "1h" }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @push = @source.monitors.find_by!(key: "nas-backup")
  end

  test "checks and state changes are newest first, with the listed fields" do
    travel_to 2.hours.ago do
      @splat.record(Uptime::Result.new(status: "up", latency_ms: 12))
    end
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))

    history = Readout::History.new(@splat).to_h

    assert_equal %w[ down up ], history[:checks].map { |check| check[:status] }
    assert_equal %i[ status at message latency_ms value duration_ms ], history[:checks].first.keys
    assert_equal [ [ "up", "down" ], [ "pending", "up" ] ], history[:state_changes].map { |change| [ change[:from], change[:to] ] }
    assert_equal %i[ from to at message ], history[:state_changes].first.keys
    assert_equal ReadoutTest::MONITOR_FIELDS + %i[ interval_seconds timeout_seconds ], history[:monitor].keys
    assert_equal 1, history[:monitor][:down_in_24h]
  end

  test "how many, and how far back" do
    travel_to 3.hours.ago do
      @splat.record(Uptime::Result.new(status: "up"))
    end
    3.times { @splat.record(Uptime::Result.new(status: "up")) }

    assert_equal 2, Readout::History.new(@splat, checks: 2).checks.size
    assert_equal 3, Readout::History.new(@splat, hours: 1).checks.size
    assert_equal 0, Readout::History.new(@splat, hours: 1).state_changes.size
    assert_equal 4, Readout::History.new(@splat).checks.size
  end

  test "a push monitor's history carries its push readout in place of interval and timeout" do
    monitor = Readout::History.new(@push).to_h[:monitor]

    assert_equal ReadoutTest::MONITOR_FIELDS + %i[ push ], monitor.keys
    assert_equal({ every_seconds: 3600 }, monitor[:push][:expected])
  end

  test "the chart's checks are the latest, oldest first" do
    travel_to 1.hour.ago do
      @splat.record(Uptime::Result.new(status: "up", latency_ms: 10))
    end
    @splat.record(Uptime::Result.new(status: "up", latency_ms: 20))

    assert_equal [ 10, 20 ], Readout::History.new(@splat).chart_checks.map(&:latency_ms)
  end
end
