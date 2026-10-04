class AddPushToUptimeMonitors < ActiveRecord::Migration[8.1]
  def change
    # Push monitors (ADR 0012): silence past interval + grace is missed.
    add_column :uptime_monitors, :grace, :integer, null: false, default: 0
    add_column :uptime_monitors, :last_pushed_at, :datetime
    # A push arrives by its token's digest (the target).
    add_index :uptime_monitors, [ :kind, :target ]

    # When the scheduler last ran. A gap means Pedant (or its jobs) was down,
    # and pushes sent meanwhile were lost (ADR 0012).
    create_table :uptime_clocks do |t|
      t.datetime :ticked_at, null: false
    end
  end
end
