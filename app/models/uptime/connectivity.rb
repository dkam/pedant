require "socket"

# Whether Pedant itself can reach the world. A failed check while Pedant is
# offline is recorded as unknown rather than down, so Pedant's own outage
# doesn't read as everything failing at once (ADR 0008).
#
# Two reference targets run by different operators (Cloudflare and Quad9). A
# TCP connection to either is enough. The answer is kept for CACHE_FOR, so an
# outage costs one probe rather than one per monitor.
#
# The targets are names, dialled as a check dials, so Pedant is offline too
# when it can't look a name up: when its resolver fails, or when it can't
# start the thread a lookup runs in (#20, ADR 0008's amendment).
module Uptime::Connectivity
  TARGETS = [ [ "one.one.one.one", 443 ], [ "dns.quad9.net", 443 ] ].freeze
  CACHE_FOR = 30.seconds

  PROBE = ->(host, port) do
    Uptime::TcpCheck.dial.call(host, port, 3)
    true
  rescue SystemCallError, SocketError, IOError, ThreadError
    false
  end
  mattr_accessor :probe, default: PROBE

  @lock = Mutex.new

  class << self
    def online?
      @lock.synchronize do
        if @checked_at.nil? || @checked_at < CACHE_FOR.ago
          @online = TARGETS.any? { |host, port| probe.call(host, port) }
          @checked_at = Time.current
        end
        @online
      end
    end

    def reset
      @lock.synchronize { @checked_at = nil }
    end
  end
end
