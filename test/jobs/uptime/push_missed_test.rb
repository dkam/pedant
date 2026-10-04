require "test_helper"

# Silence past interval + grace is missed (ADR 0012), unless Pedant itself was
# down, in which case each push monitor gets one full interval first.
class Uptime::PushMissedTest < ActiveJob::TestCase
  setup do
    @token, digest = push_token
    @source = monitor_source("monitors.yml" => { "nas-backup" => { "push" => digest, "interval" => 3600, "grace" => 600 } })
    @source.sync!
    @monitor = @source.monitors.sole
    # The first push comes a day after the monitor was defined, so "how long
    # since the last push" and "how long since it was created" differ.
    travel 1.day
    @monitor.record_push(Uptime::Result.new(status: "up"))
  end

  test "a push monitor heard from within interval plus grace stays up" do
    travel 3599.seconds + 600 do
      tick
    end

    assert_equal "up", @monitor.reload.state
  end

  test "silence past interval plus grace is down, saying for how long" do
    travel 3601.seconds + 600 do
      tick
    end

    @monitor.reload
    assert_equal "down", @monitor.state
    assert_equal "No push for 1 hour and 10 minutes", @monitor.last_message
  end

  test "after a gap in Pedant's own scheduler, an overdue push monitor gets one full interval" do
    Uptime::Clock.tick!

    travel 2.hours
    tick
    assert_equal "up", @monitor.reload.state
    assert_equal (3600 + 600).seconds.from_now.to_i, @monitor.next_check_at.to_i

    running_for 71.minutes
    assert_equal "down", @monitor.reload.state
  end

  test "a missed push is noticed while Pedant is running normally" do
    Uptime::Clock.tick!

    running_for 71.minutes

    assert_equal "down", @monitor.reload.state
  end

  test "active checks aren't held back by a gap" do
    http = monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } } }, "other").tap(&:sync!).monitors.sole
    stub_request(:get, http.target).to_return(status: 200)
    Uptime::Clock.tick!

    travel 2.hours do
      tick
    end

    assert_equal "up", http.reload.state
  end

  private
    # The scheduler ticking once a minute, as it does (more often) for real.
    def running_for(duration)
      (duration / 1.minute).to_i.times { travel 1.minute; tick }
    end

    def tick
      perform_enqueued_jobs { Uptime::ScheduleChecksJob.perform_now }
    end
end
