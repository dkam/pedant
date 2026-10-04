# The outcome of one check or push: up, warn (a value past its warn limit),
# down, or unknown (Pedant couldn't tell). A push may carry a value and, if
# the run was started with status=start, its duration.
class Uptime::Result < Data.define(:status, :latency_ms, :message, :value, :duration_ms)
  STATUSES = %w[ up warn down unknown ].freeze

  def initialize(status:, latency_ms: nil, message: nil, value: nil, duration_ms: nil)
    raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)
    super
  end

  def down? = status == "down"
end
