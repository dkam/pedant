# Queues a check for every monitor that's due. Runs every 15 seconds
# (config/recurring.yml). See Uptime::Monitor#claim_for_check for why a
# monitor isn't queued twice.
#
# After a gap in its own running (Uptime::Clock), every push monitor first
# gets one full interval plus grace from now, since pushes sent while Pedant
# was down never arrived.
class Uptime::ScheduleChecksJob < ApplicationJob
  queue_as :checks

  def perform
    now = Time.current
    restart_push_clocks(now) if Uptime::Clock.gap_before?(Uptime::Clock.tick!(now), now)

    Uptime::Monitor.active.where(next_check_at: ..now).find_each do |monitor|
      Uptime::CheckJob.perform_later(monitor) if monitor.claim_for_check
    end
  end

  private
    def restart_push_clocks(now)
      Uptime::Monitor.active.where(kind: "push").find_each do |monitor|
        due = monitor.next_due_from(now)
        monitor.update_columns(next_check_at: due) if monitor.next_check_at.nil? || monitor.next_check_at < due
      end
    end
end
