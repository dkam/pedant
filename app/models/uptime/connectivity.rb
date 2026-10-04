require "socket"

# Whether Pedant itself can reach the world. A failed check while Pedant is
# offline is recorded as unknown rather than down, so Pedant's own outage
# doesn't read as everything failing at once (CLAUDE.md, ADR 0013).
#
# Two reference targets run by different operators (Cloudflare and Quad9). A
# TCP connection to either is enough. The answer is kept for CACHE_FOR, so an
# outage costs one probe rather than one per monitor.
module Uptime::Connectivity
  TARGETS = [ [ "1.1.1.1", 443 ], [ "9.9.9.9", 443 ] ].freeze
  CACHE_FOR = 30.seconds

  mattr_accessor :probe, default: ->(host, port) do
    Socket.tcp(host, port, connect_timeout: 3).close
    true
  rescue SystemCallError, SocketError, IOError
    false
  end

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
