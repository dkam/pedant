require "test_helper"

# A push monitor on a cron schedule is expected after each scheduled time,
# plus grace, so the days it doesn't run aren't missed.
class Uptime::PushScheduleTest < ActiveJob::TestCase
  SYDNEY = ActiveSupport::TimeZone["Australia/Sydney"]

  setup do
    _token, digest = push_token
    @source = monitor_source("monitors.yml" => {
      "nightly" => { "push" => digest, "schedule" => "0 2 * * 1-5", "timezone" => "Australia/Sydney", "grace" => "30m" }
    })
  end

  test "a weekday job pushed on Friday isn't missed over the weekend, and is on Monday" do
    at sydney(2026, 10, 9, 2, 10) do # Friday, after the run
      @source.sync!
      monitor.record_push(Uptime::Result.new(status: "up"))
    end

    at(sydney(2026, 10, 11, 23, 0)) { tick } # Sunday night
    assert_equal "up", monitor.reload.state

    at(sydney(2026, 10, 12, 2, 29)) { tick } # Monday, within grace
    assert_equal "up", monitor.reload.state

    at(sydney(2026, 10, 12, 2, 31)) { tick } # Monday, past grace
    assert_equal "down", monitor.reload.state
  end

  test "after a push, the next one is expected after the next scheduled time" do
    at sydney(2026, 10, 12, 2, 5) do # Monday
      @source.sync!
      monitor.record_push(Uptime::Result.new(status: "up"))

      assert_equal sydney(2026, 10, 13, 2, 30), monitor.reload.next_check_at
    end
  end

  test "the dashboard says when it's expected" do
    at sydney(2026, 10, 12, 2, 5) do
      @source.sync!
      assert_equal "0 2 * * 1-5 (Australia/Sydney)", monitor.schedule_in_words
    end
  end

  private
    def monitor = @source.monitors.sole

    def sydney(*parts) = SYDNEY.local(*parts)

    def at(time, &)
      travel_to(time, &)
    end

    # The scheduler running normally: the clock last ticked 15 seconds ago.
    def tick
      Uptime::Clock.tick!(15.seconds.ago)
      perform_enqueued_jobs { Uptime::ScheduleChecksJob.perform_now }
    end
end
