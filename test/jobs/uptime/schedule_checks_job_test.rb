require "test_helper"

class Uptime::ScheduleChecksJobTest < ActiveJob::TestCase
  setup do
    @source = monitor_source("monitors.yml" => {
      "due" => { "http" => "http://splat.local:3030/up" },
      "later" => { "http" => "http://splat.local:3040/up" },
      "retired" => { "http" => "http://splat.local:3050/up" }
    })
    @source.sync!
    @source.monitors.find_by!(key: "later").update!(next_check_at: 1.minute.from_now)
    @source.monitors.find_by!(key: "retired").update!(retired_at: Time.current)
  end

  test "only due, active monitors are queued" do
    due = @source.monitors.find_by!(key: "due")

    assert_enqueued_with(job: Uptime::CheckJob, args: [ due ]) do
      Uptime::ScheduleChecksJob.perform_now
    end
    assert_enqueued_jobs 1, only: Uptime::CheckJob
  end

  test "a queued monitor isn't queued again before its check has run" do
    Uptime::ScheduleChecksJob.perform_now
    Uptime::ScheduleChecksJob.perform_now

    assert_enqueued_jobs 1, only: Uptime::CheckJob
  end

  test "a check that never reports back is queued again after its timeout" do
    Uptime::ScheduleChecksJob.perform_now

    travel 2.minutes do
      Uptime::ScheduleChecksJob.perform_now
    end

    assert_enqueued_jobs 3, only: Uptime::CheckJob # due twice, and later once
  end

  # One refresh per tick rather than one per check: checks finishing seconds
  # apart on different workers morphed the dashboard every few seconds (#10).
  test "a tick refreshes the dashboards once if anything was recorded since the last tick" do
    push_source = monitor_source({ "monitors.yml" => { "backup" => { "push" => push_token.last, "interval" => 3600 } } }, "nas")
    push_source.sync!
    due, later, backup = @source.monitors.find_by!(key: "due"), @source.monitors.find_by!(key: "later"), push_source.monitors.sole
    Uptime::ScheduleChecksJob.perform_now

    travel 5.seconds do
      due.record Uptime::Result.new(status: "up")
      later.record Uptime::Result.new(status: "up")
    end
    travel 15.seconds do
      assert_turbo_stream_broadcasts(:monitors, count: 1) { Uptime::ScheduleChecksJob.perform_now }
    end

    # An unchanged result still refreshes: the "ago" times and recent checks move on.
    travel 20.seconds do
      due.record Uptime::Result.new(status: "up")
    end
    travel 30.seconds do
      assert_turbo_stream_broadcasts(:monitors, count: 1) { Uptime::ScheduleChecksJob.perform_now }
    end

    # So does a run's start, which records no check.
    travel 35.seconds do
      backup.start_run!
    end
    travel 45.seconds do
      assert_turbo_stream_broadcasts(:monitors, count: 1) { Uptime::ScheduleChecksJob.perform_now }
    end
  end

  test "a tick with nothing recorded since the last one doesn't refresh" do
    Uptime::ScheduleChecksJob.perform_now

    travel 15.seconds do
      assert_turbo_stream_broadcasts(:monitors, count: 0) { Uptime::ScheduleChecksJob.perform_now }
    end
  end
end
