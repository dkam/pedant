class AddValuesRunsAndSchedulesToUptime < ActiveRecord::Migration[8.1]
  def change
    # A push can carry a measurement (value=87), and a finished run its
    # duration since status=start.
    add_column :uptime_checks, :value, :float
    add_column :uptime_checks, :duration_ms, :integer
    add_column :uptime_monitors, :last_value, :float
    add_column :uptime_monitors, :started_at, :datetime

    # A push monitor on a cron schedule has no interval.
    change_column_null :uptime_monitors, :interval, true
  end
end
