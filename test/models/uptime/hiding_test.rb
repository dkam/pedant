require "test_helper"

# A down monitor can be hidden for its current outage (dkam/pedant#17, ADR
# 0033): no reminders until its next run, or for a day. Recovering ends it,
# and if it ends while the monitor is still down, a reminder goes out at once.
class Uptime::HidingTest < ActiveJob::TestCase
  setup do
    @token, digest = push_token
    monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0, "remind_every" => "6h" },
      "quiet" => { "name" => "Quiet", "http" => "http://splat.local:3040/up", "retries" => 0, "remind_every" => "never" },
      "slow" => { "name" => "Slow", "http" => "http://splat.local:3060/up", "retries" => 0, "remind_every" => "3d" },
      "backup" => { "name" => "pg02 backup", "push" => digest, "interval" => "26h", "grace" => 60 }
    }).sync!
    monitor("splat").record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    monitor("quiet").record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    monitor("slow").record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    push("backup", status: "down", message: "backup of booko_production.dump failed")
  end

  test "hidden for a day, a down monitor sends no reminders, then one as soon as the day is up" do
    splat = monitor("splat")
    assert splat.hide!

    assert splat.hidden?
    travel 23.hours
    assert_no_difference(-> { reminders_for("splat") }) { SendRemindersJob.perform_now }

    travel 1.hour + 1.minute
    assert_difference(-> { reminders_for("splat") }, 1) { SendRemindersJob.perform_now }
    assert_not monitor("splat").hidden?

    travel 5.hours
    assert_no_difference(-> { reminders_for("splat") }, "then every remind_every again") { SendRemindersJob.perform_now }
    travel 1.hour + 1.minute
    assert_difference(-> { reminders_for("splat") }, 1) { SendRemindersJob.perform_now }
  end

  test "the end of a hide reminds even when remind_every is longer, and then the hide is gone" do
    monitor("slow").hide!

    travel 1.day + 1.minute
    assert_difference(-> { reminders_for("slow") }, 1) { SendRemindersJob.perform_now }
    assert_nil monitor("slow").hidden_until

    travel 2.days
    assert_no_difference(-> { reminders_for("slow") }, "then every 3 days from that reminder") { SendRemindersJob.perform_now }
  end

  test "a hide that ends doesn't remind a monitor whose reminders are off" do
    monitor("quiet").hide!

    travel 25.hours
    SendRemindersJob.perform_now

    assert_equal 0, reminders_for("quiet")
  end

  test "recovering ends a hide, with the usual recovery alert, and the next outage isn't hidden" do
    splat = monitor("splat")
    splat.hide!

    assert_difference(-> { Alert.where(kind: "recovered").count }, 1) { splat.record(Uptime::Result.new(status: "up")) }
    assert_not splat.reload.hidden?

    assert_difference(-> { Alert.where(kind: "down").count }, 1) { splat.record(Uptime::Result.new(status: "down", message: "HTTP 503")) }
    assert_not splat.reload.hidden?
  end

  test "hidden until its next run, a push monitor's next failure reminds at once" do
    assert monitor("backup").hide!(until_next_run: true)
    travel 25.hours
    assert_no_difference(-> { reminders_for("backup") }, "the daily reminder waits for the run") { SendRemindersJob.perform_now }

    assert_difference(-> { reminders_for("backup") }, 1) { push("backup", status: "down", message: "backup of booko_production.dump failed") }
    assert_not monitor("backup").hidden?
    assert_match "backup of booko_production.dump failed", Alert.where(kind: "reminder").last.message
  end

  test "hidden until its next run, a push monitor's next success is its recovery" do
    monitor("backup").hide!(until_next_run: true)
    travel 25.hours

    assert_difference(-> { Alert.where(kind: "recovered").count }, 1) { push("backup", status: "up") }
    assert_equal 0, reminders_for("backup")
    assert_not monitor("backup").hidden?
  end

  test "hidden until its next run, a run that doesn't come reminds once it's overdue" do
    backup = monitor("backup")
    backup.hide!(until_next_run: true)

    assert_equal backup.next_check_at, backup.hidden_until, "the time its next push counts as missed"
    travel 26.hours
    assert_no_difference(-> { reminders_for("backup") }) { SendRemindersJob.perform_now }

    travel 2.minutes
    assert_difference(-> { reminders_for("backup") }, 1) { SendRemindersJob.perform_now }
  end

  test "hidden for a day, a push monitor's pushes don't end it" do
    monitor("backup").hide!
    travel 1.hour

    assert_no_difference(-> { reminders_for("backup") }) { push("backup", status: "down", message: "still failing") }
    assert monitor("backup").hidden?
  end

  test "only a down monitor can be hidden, and only a push monitor until its next run" do
    monitor("splat").record(Uptime::Result.new(status: "up"))

    assert_not monitor("splat").hide!
    assert_not monitor("quiet").hide!(until_next_run: true)
    assert_not monitor("splat").reload.hidden?
    assert_not monitor("quiet").reload.hidden?
  end

  test "showing it again brings reminders back on their usual schedule" do
    splat = monitor("splat")
    splat.hide!
    travel 7.hours

    assert_no_difference(-> { reminders_for("splat") }, "nothing goes out for having been hidden") { splat.show_again! }
    assert_not splat.hidden?
    assert_difference(-> { reminders_for("splat") }, 1, "it's been down 7 hours, past remind_every") { SendRemindersJob.perform_now }
  end

  private
    def monitor(key) = Uptime::Monitor.find_by!(key: key)

    def push(key, status:, message: nil)
      monitor = monitor(key)
      monitor.record_push(monitor.push_result(status: status, message: message))
    end

    def reminders_for(key) = Alert.where(kind: "reminder", monitor: monitor(key)).count
end
