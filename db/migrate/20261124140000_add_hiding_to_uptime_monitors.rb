# Hiding a down monitor for its current outage (ADR 0033).
class AddHidingToUptimeMonitors < ActiveRecord::Migration[8.1]
  def change
    add_column :uptime_monitors, :hidden_at, :datetime
    add_column :uptime_monitors, :hidden_until, :datetime
    add_column :uptime_monitors, :hidden_until_next_push, :boolean, default: false, null: false
  end
end
