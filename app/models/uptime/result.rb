# The outcome of one check: up, down or unknown (Pedant couldn't tell).
class Uptime::Result < Data.define(:status, :latency_ms, :message)
  STATUSES = %w[ up down unknown ].freeze

  def initialize(status:, latency_ms: nil, message: nil)
    raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)
    super
  end

  def down? = status == "down"
end
