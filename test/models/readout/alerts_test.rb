require "test_helper"

class Readout::AlertsTest < ActiveSupport::TestCase
  setup do
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "kith" => { "name" => "Kith", "http" => "http://splat.local:3040/up", "retries" => 0 }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @kith = @source.monitors.find_by!(key: "kith")
    @ntfy = ntfy_channel!
    @email = email_channel!(enabled: false)
  end

  test "alerts are newest first, with their deliveries per channel and the listed fields" do
    travel_to 1.hour.ago do
      @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    end
    @splat.record(Uptime::Result.new(status: "up"))
    down = Alert.find_by!(kind: "down")
    @ntfy.deliveries.create!(alert: down, status: "failed", error: "Timed out after 10s", attempt: 1, attempted_at: 50.minutes.ago)
    @ntfy.deliveries.create!(alert: down, status: "sent", attempt: 2, attempted_at: 40.minutes.ago)

    alerts = Readout::Alerts.new.to_h[:alerts]

    assert_equal %w[ recovered down ], alerts.map { |alert| alert[:kind] }
    assert_equal %i[ id kind title message created_at monitor deliveries ], alerts.last.keys
    assert_equal({ id: @splat.id, key: "splat", name: "Splat" }, alerts.last[:monitor])
    assert_equal [ [ "ntfy", "failed", 1 ], [ "ntfy", "sent", 2 ] ],
      alerts.last[:deliveries].map { |delivery| delivery.values_at(:channel, :status, :attempt) }
    assert_equal %i[ channel status attempt attempted_at error ], alerts.last[:deliveries].first.keys
  end

  test "each channel says whether it's enabled and how its last delivery went, and nothing else" do
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @ntfy.deliveries.create!(alert: Alert.sole, status: "failed", error: "HTTP 500: oops", attempt: 1, attempted_at: Time.current)

    channels = Readout::Alerts.new.to_h[:channels]

    assert_equal [ "email", "ntfy" ], channels.map { |channel| channel[:channel] }
    email, ntfy = channels
    assert_equal({ channel: "email", enabled: false, failing: false, last_delivery: nil }, email)
    assert_equal true, ntfy[:failing]
    assert_equal "HTTP 500: oops", ntfy[:last_delivery][:error]
  end

  test "a delivery error has the channel's URL and secret taken out" do
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @ntfy.deliveries.create!(alert: Alert.sole, status: "failed", attempt: 1, attempted_at: Time.current,
      error: "HTTP 401: ntfy-secret-token is no good for #{AlertChannels::NTFY_URL} (ntfy.example.test/pedant)")
    @email.deliveries.create!(alert: Alert.sole, status: "failed", attempt: 1, attempted_at: Time.current,
      error: "535 smtp-password rejected")

    errors = Readout::Alerts.new.to_h[:alerts].sole[:deliveries].map { |delivery| delivery[:error] }

    assert_equal [ "HTTP 401: [FILTERED] is no good for [FILTERED] ([FILTERED])", "535 [FILTERED] rejected" ], errors
  end

  test "filtered by monitor, kind and time, and limited" do
    travel_to 3.hours.ago do
      @kith.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    end
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @splat.record(Uptime::Result.new(status: "up"))

    assert_equal %w[ recovered down ], Readout::Alerts.new(monitor: @splat).alerts.map(&:kind)
    assert_equal %w[ Kith Splat ].sort, Readout::Alerts.new(kind: "down").alerts.map { |alert| alert.monitor.name }.sort
    assert_equal 2, Readout::Alerts.new(hours: 1).alerts.size
    assert_equal 1, Readout::Alerts.new(limit: 1).alerts.size
  end

  test "an alert with no monitor, a test, has none" do
    Alert.create!(kind: "test", title: "Test alert from Pedant", message: "If you can read this, ntfy alerts work.")

    assert_nil Readout::Alerts.new.to_h[:alerts].sole[:monitor]
  end
end
