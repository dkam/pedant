# While a monitor stays down, a reminder every remind_every (a day unless
# monitors.yml says otherwise; "never" turns them off). A single alert is
# easily lost (ADR 0013). Not while unknown: that's Pedant's own outage.
class SendRemindersJob < ApplicationJob
  queue_as :alerts

  def perform(now = Time.current)
    Uptime::Monitor.active.where(state: "down").where.not(outage_started_at: nil).find_each do |monitor|
      monitor.remind_if_due(now)
    end
  end
end
