require "test_helper"

# When an alert is raised (ADR 0013): on going down (after retries), on
# recovery, never for unknown, and once per outage.
class OutageAlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    source = monitor_source("monitors.yml" => { "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 1 } })
    source.sync!
    @monitor = source.monitors.sole
  end

  test "going down raises one down alert, saying why" do
    @monitor.record(result("up"))

    assert_difference -> { Alert.count }, 1 do
      2.times { @monitor.record(result("down", "HTTP 503")) }
    end

    alert = Alert.last
    assert_equal [ "down", @monitor, "Splat is down" ], [ alert.kind, alert.monitor, alert.title ]
    assert_match "HTTP 503", alert.message
  end

  test "a failure still within retries raises nothing" do
    @monitor.record(result("up"))

    assert_no_difference(-> { Alert.count }) { @monitor.record(result("down")) }
  end

  test "staying down raises nothing more" do
    2.times { @monitor.record(result("down")) }

    assert_no_difference(-> { Alert.count }) { 3.times { @monitor.record(result("down")) } }
  end

  test "recovery raises one alert saying how long it was down" do
    2.times { @monitor.record(result("down")) }

    travel 12.minutes
    assert_difference(-> { Alert.count }, 1) { @monitor.record(result("up")) }

    alert = Alert.last
    assert_equal [ "recovered", "Splat is back up" ], [ alert.kind, alert.title ]
    assert_match "Down for 12 minutes", alert.message
    assert_nil @monitor.outage_started_at
  end

  test "unknown raises nothing, and doesn't end an outage" do
    2.times { @monitor.record(result("down")) }

    assert_no_difference -> { Alert.count } do
      @monitor.record(result("unknown"))
      2.times { @monitor.record(result("down")) }
    end
    assert_difference(-> { Alert.count }, 1) { @monitor.record(result("up")) }
  end

  test "unknown on its own, and back, raises nothing" do
    @monitor.record(result("up"))

    assert_no_difference -> { Alert.count } do
      @monitor.record(result("unknown"))
      @monitor.record(result("up"))
    end
  end

  test "a first result of up raises nothing; a first result of down alerts" do
    assert_no_difference(-> { Alert.count }) { @monitor.record(result("up")) }

    other = monitor_source({ "monitors.yml" => { "kith" => { "http" => "http://splat.local:3040/up", "retries" => 0 } } }, "other").tap(&:sync!).monitors.sole
    assert_difference(-> { Alert.count }, 1) { other.record(result("down")) }
  end

  test "warn after down is a recovery; warn after up raises nothing" do
    @monitor.record(result("up"))
    assert_no_difference(-> { Alert.count }) { @monitor.record(result("warn")) }

    2.times { @monitor.record(result("down")) }
    @monitor.record(result("warn"))

    assert_equal "recovered", Alert.last.kind
  end

  test "an alert is queued for delivery through each enabled channel" do
    ntfy = ntfy_channel!
    email = email_channel!

    assert_enqueued_jobs 2, only: DeliverAlertJob do
      2.times { @monitor.record(result("down")) }
    end
    assert_enqueued_with(job: DeliverAlertJob, args: [ Alert.last, ntfy ])
    assert_enqueued_with(job: DeliverAlertJob, args: [ Alert.last, email ])
  end

  test "a disabled channel isn't used, and with no channels the alert is still kept" do
    ntfy_channel!(enabled: false)

    assert_no_enqueued_jobs(only: DeliverAlertJob) { 2.times { @monitor.record(result("down")) } }
    assert_equal 1, Alert.count
  end

  # The job queue is a separate database, so a job queued inside a transaction
  # that rolls back would still run, alerting about a change that never happened.
  test "nothing is sent for an alert whose transaction rolls back" do
    ntfy_channel!

    assert_no_enqueued_jobs only: DeliverAlertJob do
      Alert.transaction do
        Alert.create!(monitor: @monitor, kind: "down", title: "Splat is down")
        raise ActiveRecord::Rollback
      end
    end
  end

  private
    def result(status, message = nil) = Uptime::Result.new(status: status, message: message)
end
