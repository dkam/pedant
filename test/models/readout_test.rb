require "test_helper"

# The read side (ADR 0025). The field lists are spelled out here on purpose: a
# field added to a readout is a deliberate change to this test, never a
# column that turned up in the output by itself.
class ReadoutTest < ActiveSupport::TestCase
  MONITOR_FIELDS = %i[
    id key name kind target defined_in state state_since retired_at outage_started_at failures_in_a_row retries
    down_in_24h down_in_7d last_checked_at last_message last_latency_ms last_value last_pushed_at
  ].freeze

  setup do
    _token, @digest = push_token
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "kith" => { "http" => "http://splat.local:3040/up" },
      "nas-backup" => { "push" => @digest, "interval" => "1h" }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @kith = @source.monitors.find_by!(key: "kith")
    @push = @source.monitors.find_by!(key: "nas-backup")
  end

  test "a monitor's fields are the listed ones" do
    assert_equal MONITOR_FIELDS, Readout.monitor(@splat, flaps: { day: 0, week: 0 }).keys
  end

  test "a push monitor's target, its token's digest, is left out" do
    readout = Readout.monitor(@push, flaps: { day: 0, week: 0 })

    assert_nil readout[:target]
    assert_not_includes readout.values.map(&:to_s).join, @digest.delete_prefix("sha256:")
  end

  test "an http monitor's target is shown as git has it" do
    assert_equal "http://splat.local:3030/up", Readout.monitor(@splat, flaps: { day: 0, week: 0 })[:target]
  end

  test "flaps count going down in the last day and week, for many monitors at once" do
    travel_to 3.days.ago do
      @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
      @splat.record(Uptime::Result.new(status: "up"))
    end
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))

    flaps = Readout.flaps_for([ @splat, @kith ])

    assert_equal({ day: 1, week: 2 }, flaps[@splat.id])
    assert_equal({ day: 0, week: 0 }, flaps[@kith.id])
    assert_equal @splat.flaps, flaps[@splat.id][:day]
    assert_equal @splat.flaps(within: 7.days), flaps[@splat.id][:week]
  end

  test "flaps count an outage still open from before the window, for many monitors at once" do
    travel_to 30.days.ago do
      @splat.record(Uptime::Result.new(status: "down", message: "HTTP 502"))
    end
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 502"))

    assert_equal({ day: 1, week: 1 }, Readout.flaps_for([ @splat, @kith ])[@splat.id])
  end

  test "a monitor is found by key or by id" do
    assert_equal @splat, Readout.find_monitor("splat")
    assert_equal @splat, Readout.find_monitor(@splat.id.to_s)
    assert_equal @splat, Readout.find_monitor(" splat ")
  end

  test "a key or id that names nothing is NotFound" do
    error = assert_raises(Readout::NotFound) { Readout.find_monitor("nope") }
    assert_match "nope", error.message

    assert_raises(Readout::NotFound) { Readout.find_monitor("999999") }
    assert_raises(Readout::NotFound) { Readout.find_monitor("") }
  end

  test "a key two sources share is refused with both ids, unless only one is active" do
    other = monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://other.local/up" } } }, "booko")
    other.sync!
    twin = other.monitors.sole

    error = assert_raises(Readout::NotFound) { Readout.find_monitor("splat") }
    assert_match "id #{@splat.id} in koti", error.message
    assert_match "id #{twin.id} in booko", error.message

    twin.update!(retired_at: Time.current)
    assert_equal @splat, Readout.find_monitor("splat")
  end

  test "the monitor list is down first, and leaves out retired monitors unless asked" do
    @kith.record(Uptime::Result.new(status: "up"))
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @push.update!(retired_at: Time.current)

    assert_equal %w[ splat kith ], Readout::Monitors.new.monitors.map(&:key)
    # The retired one is still pending, which comes before up.
    assert_equal %w[ splat nas-backup kith ], Readout::Monitors.new(include_retired: true).monitors.map(&:key)
    assert_equal %w[ kith ], Readout::Monitors.new(state: "up").monitors.map(&:key)
    assert_equal %w[ splat kith ], Readout::Monitors.new(kind: "http").monitors.map(&:key)
  end

  test "the counts cover every active monitor, whatever the filters" do
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))

    readout = Readout::Monitors.new(state: "down")

    assert_equal({ "down" => 1, "pending" => 2 }, readout.counts)
    assert_equal({ "down" => 1, "pending" => 2 }, readout.to_h[:counts])
    assert_equal [ "splat" ], readout.to_h[:monitors].map { |monitor| monitor[:key] }
  end
end
