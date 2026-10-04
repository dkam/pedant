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
end
