require "test_helper"

class Readout::PushTest < ActiveSupport::TestCase
  FIELDS = %i[ expected grace_seconds max_runtime_seconds last_pushed_at silent_for_seconds missed_after running_since value ].freeze

  setup do
    _token, @digest = push_token
    _other, @nightly_digest = push_token("a-nightly-push-token")
  end

  test "an interval monitor that's never been pushed to" do
    monitor = sync_one("nas-backup" => { "push" => @digest, "interval" => "1h", "grace" => "5m" })

    readout = Readout::Push.new(monitor).to_h

    assert_equal FIELDS, readout.keys
    assert_equal({ every_seconds: 3600 }, readout[:expected])
    assert_equal 300, readout[:grace_seconds]
    assert_nil readout[:last_pushed_at]
    assert_nil readout[:silent_for_seconds]
    assert_nil readout[:value]
    assert_equal monitor.next_check_at.utc.iso8601, readout[:missed_after]
  end

  test "a scheduled monitor, pushed to, with a run in progress" do
    monitor = sync_one("nightly" => { "push" => @nightly_digest, "schedule" => "0 2 * * *", "timezone" => "Australia/Sydney",
      "grace" => "1h", "max_runtime" => "3h" })
    travel_to 10.minutes.ago do
      monitor.record_push(monitor.push_result(status: "up"))
    end
    monitor.start_run!

    freeze_time do
      readout = Readout::Push.new(monitor).to_h

      assert_equal({ schedule: "0 2 * * *", timezone: "Australia/Sydney" }, readout[:expected])
      assert_equal 3 * 3600, readout[:max_runtime_seconds]
      assert_in_delta 600, readout[:silent_for_seconds], 1
      assert_equal Time.current.utc.iso8601, readout[:running_since]
    end
  end

  test "a value with its limits and forecast" do
    monitor = sync_one("nas-disk" => { "push" => @digest, "interval" => "5m",
      "value" => { "label" => "Free on /", "unit" => "GB", "down_below" => 5, "warn_below" => 20,
        "forecast" => { "reaches" => 0, "down_within" => "3d", "warn_within" => "14d" } } })
    # Free space falling 1 GB an hour from 100 GB, over the last 12 hours.
    12.downto(1) do |hours_ago|
      travel_to hours_ago.hours.ago do
        monitor.record_push(monitor.push_result(status: "up", value: (100 - (12 - hours_ago)).to_s))
      end
    end

    value = Readout::Push.new(monitor).to_h[:value]

    assert_equal %i[ label unit last shown limits forecast ], value.keys
    assert_equal "Free on /", value[:label]
    assert_equal 89.0, value[:last]
    assert_equal "89 GB", value[:shown]
    assert_equal({ "warn_below" => 20, "down_below" => 5 }, value[:limits])

    forecast = value[:forecast]
    assert_equal %i[ reaches down_within_seconds warn_within_seconds reaches_in_seconds summary ], forecast.keys
    assert_equal 3 * 86_400, forecast[:down_within_seconds]
    assert_in_delta 88.hours, forecast[:reaches_in_seconds], 2.hours
    assert_equal monitor.forecast_in_words, forecast[:summary]
  end

  private
    def sync_one(entry)
      source = monitor_source("monitors.yml" => entry)
      source.sync!
      source.monitors.sole
    end
end
