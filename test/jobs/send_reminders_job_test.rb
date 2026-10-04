require "test_helper"

# While a monitor stays down, a reminder goes out every remind_every (1 day
# unless monitors.yml says otherwise). A single alert is easily lost (ADR 0013).
class SendRemindersJobTest < ActiveJob::TestCase
  setup do
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "quick" => { "name" => "Quick", "http" => "http://splat.local:3040/up", "retries" => 0, "remind_every" => "6h" },
      "quiet" => { "name" => "Quiet", "http" => "http://splat.local:3050/up", "retries" => 0, "remind_every" => "never" }
    })
    @source.sync!
    @source.monitors.each { |monitor| monitor.record(Uptime::Result.new(status: "down", message: "HTTP 503")) }
  end

  test "a reminder goes out once remind_every has passed, and again after each period" do
    travel 23.hours
    assert_no_difference(-> { reminders_for("splat") }) { SendRemindersJob.perform_now }

    travel 2.hours
    assert_difference(-> { reminders_for("splat") }, 1) { SendRemindersJob.perform_now }
    assert_no_difference(-> { reminders_for("splat") }) { SendRemindersJob.perform_now }

    travel 1.day
    assert_difference(-> { reminders_for("splat") }, 1) { SendRemindersJob.perform_now }
  end

  test "the reminder says it's still down, for how long, and why" do
    travel 25.hours
    SendRemindersJob.perform_now

    reminder = Alert.where(kind: "reminder").joins(:monitor).find_by!(uptime_monitors: { key: "splat" })
    assert_equal "Splat is still down", reminder.title
    assert_match "Down for 1 day and 1 hour", reminder.message
    assert_match "HTTP 503", reminder.message
  end

  test "remind_every is per monitor, and never turns reminders off" do
    travel 7.hours
    SendRemindersJob.perform_now

    assert_equal 1, reminders_for("quick")
    assert_equal 0, reminders_for("splat")

    travel 30.days
    SendRemindersJob.perform_now
    assert_equal 0, reminders_for("quiet")
  end

  test "no reminders while unknown, after recovery, or for a retired monitor" do
    splat = monitor("splat")
    splat.record(Uptime::Result.new(status: "unknown"))
    monitor("quick").record(Uptime::Result.new(status: "up"))
    monitor("quiet").update!(retired_at: Time.current)

    travel 2.days
    SendRemindersJob.perform_now

    assert_equal 0, Alert.where(kind: "reminder").count
  end

  test "reminders run on the alerts queue" do
    assert_equal "alerts", SendRemindersJob.new.queue_name
  end

  private
    def monitor(key) = @source.monitors.find_by!(key: key)

    def reminders_for(key)
      Alert.where(kind: "reminder", monitor: monitor(key)).count
    end
end
