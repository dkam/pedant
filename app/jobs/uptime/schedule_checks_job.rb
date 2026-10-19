# Queues a check for every monitor that's due. Runs every 15 seconds
# (config/recurring.yml). See Uptime::Monitor#claim_for_check for why a
# monitor isn't queued twice.
#
# After a gap in its own running (Uptime::Clock), every push monitor first
# gets one full interval plus grace from now, since pushes sent while Pedant
# was down never arrived.
#
# Then it refreshes the dashboards once if anything was recorded since the
# last tick: one refresh per tick, not one per check or push, which finish
# seconds apart on different workers (#10). Unchanged results count too, as
# the "ago" times and recent checks move on.
class Uptime::ScheduleChecksJob < ApplicationJob
  queue_as :checks

  def perform
    now = Time.current
    previous = Uptime::Clock.tick!(now)
    restart_push_clocks(now) if Uptime::Clock.gap_before?(previous, now)

    Uptime::Monitor.active.where(next_check_at: ..now).find_each do |monitor|
      Uptime::CheckJob.perform_later(monitor) if monitor.claim_for_check
    end

    Turbo::StreamsChannel.broadcast_refresh_to(:monitors) if recorded_since?(previous)
  end

  private
    # Recording a check, a push or a run's start saves its monitor, so
    # updated_at moves; claiming a check (update_all) doesn't.
    def recorded_since?(previous)
      previous.nil? || Uptime::Monitor.where(updated_at: previous..).exists?
    end

    def restart_push_clocks(now)
      Uptime::Monitor.active.where(kind: "push").find_each do |monitor|
        due = monitor.next_due_from(now)
        monitor.update_columns(next_check_at: due) if monitor.next_check_at.nil? || monitor.next_check_at < due
      end
    end
end
