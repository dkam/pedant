# Runs one monitor's check and records it. A failure while Pedant itself can't
# reach the world is recorded as unknown, not down (Uptime::Connectivity).
class Uptime::CheckJob < ApplicationJob
  queue_as :checks
  discard_on ActiveJob::DeserializationError

  def perform(monitor)
    return if monitor.retired?

    result = monitor.check
    if result.down? && !Uptime::Connectivity.online?
      result = Uptime::Result.new(status: "unknown", message: "Pedant is offline: #{result.message}")
    end

    monitor.record(result)
    Turbo::StreamsChannel.broadcast_refresh_to(:monitors)
  end
end
