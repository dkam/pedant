# Runs one monitor's check and records it. A failure while Pedant itself can't
# reach the world is recorded as unknown, not down (Uptime::Connectivity).
# The dashboards refresh on the scheduler's next tick (Uptime::ScheduleChecksJob).
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
  end
end
