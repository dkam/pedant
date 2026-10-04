require "test_helper"

class Uptime::CheckJobTest < ActiveJob::TestCase
  setup do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up", "retries" => 0 } })
    source.sync!
    @monitor = source.monitors.sole
  end

  test "it checks the monitor and records the result" do
    stub_request(:get, @monitor.target).to_return(status: 200)

    Uptime::CheckJob.perform_now(@monitor)

    assert_equal "up", @monitor.reload.state
  end

  test "a failure while Pedant can reach the world is down" do
    stub_request(:get, @monitor.target).to_raise(Errno::ECONNREFUSED)

    Uptime::CheckJob.perform_now(@monitor)

    assert_equal "down", @monitor.reload.state
  end

  test "a failure while Pedant itself is offline is unknown, not down" do
    stub_request(:get, @monitor.target).to_timeout
    pedant_offline!

    Uptime::CheckJob.perform_now(@monitor)

    @monitor.reload
    assert_equal "unknown", @monitor.state
    assert_match(/Pedant/, @monitor.last_message)
    assert_equal 0, @monitor.consecutive_failures
  end

  test "a retired monitor isn't checked" do
    @monitor.update!(retired_at: Time.current)

    Uptime::CheckJob.perform_now(@monitor)

    assert_empty @monitor.checks
  end

  test "checks run on their own queue" do
    assert_equal "checks", Uptime::CheckJob.new.queue_name
  end
end
