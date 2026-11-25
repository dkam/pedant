require "test_helper"

class Uptime::ConnectivityTest < ActiveSupport::TestCase
  DIAL = Uptime::TcpCheck.dial
  teardown { Uptime::TcpCheck.dial = DIAL }

  # Out of threads, Ruby can't resolve a name (getaddrinfo runs in a thread of
  # its own), and Socket.tcp can't start the threads it tries addresses in.
  # Either way Pedant can't tell, so it's offline, not a job that fails.
  test "the probe finds Pedant offline when it can't look the name up, or start a thread to" do
    [ SocketError.new("getaddrinfo(3): Temporary failure in name resolution"),
      ThreadError.new("can't create Thread: Resource temporarily unavailable") ].each do |error|
      Uptime::TcpCheck.dial = ->(*) { raise error }

      assert_equal false, Uptime::Connectivity::PROBE.call("one.one.one.one", 443), error.class.name
    end
  end
  test "Pedant is online if it can reach any reference target" do
    reached = []
    Uptime::Connectivity.probe = ->(host, _port) { reached << host; host == Uptime::Connectivity::TARGETS.last.first }
    Uptime::Connectivity.reset

    assert Uptime::Connectivity.online?
    assert_equal Uptime::Connectivity::TARGETS.map(&:first), reached
  end

  test "Pedant is offline if it reaches none of them" do
    pedant_offline!

    assert_not Uptime::Connectivity.online?
  end

  test "the answer is remembered briefly, so an outage doesn't probe once per monitor" do
    calls = 0
    Uptime::Connectivity.probe = ->(_host, _port) { calls += 1; true }
    Uptime::Connectivity.reset

    3.times { Uptime::Connectivity.online? }
    assert_equal 1, calls

    travel 31.seconds do
      Uptime::Connectivity.online?
    end
    assert_equal 2, calls
  end

  test "the reference targets are run by different operators" do
    assert_operator Uptime::Connectivity::TARGETS.map(&:first).uniq.size, :>=, 2
  end
end
