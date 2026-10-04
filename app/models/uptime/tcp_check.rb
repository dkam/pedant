require "socket"

# One TCP check: open a connection to host:port and close it. For services
# with no HTTP endpoint, such as Postgres, PgBouncer, Redis and beanstalkd.
class Uptime::TcpCheck
  # Swappable so tests needn't reach the network, like Connectivity.probe.
  mattr_accessor :dial, default: ->(host, port, timeout) { Socket.tcp(host, port, connect_timeout: timeout).close }

  def initialize(target:, timeout:)
    @host, port = target.rpartition(":").values_at(0, 2)
    @port = Integer(port)
    @timeout = timeout
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dial.call(@host, @port, @timeout)
    Uptime::Result.new(status: "up", latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
  rescue Errno::ETIMEDOUT, IO::TimeoutError
    down "Timed out after #{@timeout}s"
  rescue Errno::ECONNREFUSED
    down "Connection refused"
  rescue SocketError, SystemCallError, IOError => error
    down error.message.presence || error.class.name
  end

  private
    def down(message)
      Uptime::Result.new(status: "down", message: message)
    end
end
