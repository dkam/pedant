require "test_helper"
require "socket"

class Uptime::TcpCheckTest < ActiveSupport::TestCase
  teardown { Uptime::TcpCheck.dial = DIAL }

  DIAL = Uptime::TcpCheck.dial

  test "a port that accepts a connection is up, with how long it took" do
    server = TCPServer.new("127.0.0.1", 0)

    result = check("127.0.0.1:#{server.addr[1]}")

    assert_equal "up", result.status
    assert_kind_of Integer, result.latency_ms
    assert_nil result.message
  ensure
    server&.close
  end

  test "a closed port is down: connection refused" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    result = check("127.0.0.1:#{port}")

    assert_equal "down", result.status
    assert_equal "Connection refused", result.message
  end

  test "no answer in time is down, and says how long it waited" do
    Uptime::TcpCheck.dial = ->(*) { raise Errno::ETIMEDOUT }

    result = check("pg01:5432")

    assert_equal "down", result.status
    assert_equal "Timed out after 10s", result.message
  end

  test "a name that doesn't resolve is down, and says so" do
    Uptime::TcpCheck.dial = ->(*) { raise Socket::ResolutionError, "getaddrinfo: Name or service not known" }

    result = check("no-such-host.invalid:5432")

    assert_equal "down", result.status
    assert_match(/not known/, result.message)
  end

  test "the host, port and timeout are what's dialled" do
    dialled = nil
    Uptime::TcpCheck.dial = ->(*args) { dialled = args }

    check("100.111.0.120:11300", timeout: 4)

    assert_equal [ "100.111.0.120", 11300, 4 ], dialled
  end

  private
    def check(target, timeout: 10)
      Uptime::TcpCheck.new(target: target, timeout: timeout).call
    end
end
