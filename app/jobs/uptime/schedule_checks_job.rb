# Queues a check for every monitor that's due. Runs every 15 seconds
# (config/recurring.yml). See Uptime::Monitor#claim_for_check for why a
# monitor isn't queued twice.
class Uptime::ScheduleChecksJob < ApplicationJob
  queue_as :checks

  def perform
    Uptime::Monitor.active.where(next_check_at: ..Time.current).find_each do |monitor|
      Uptime::CheckJob.perform_later(monitor) if monitor.claim_for_check
    end
  end
end
