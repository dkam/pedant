class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    # ntfy and email (ADR 0013). Pedant's own configuration, not fleet intent:
    # STI by channel, non-secret settings as JSON, the one secret encrypted.
    create_table :alert_channels do |t|
      t.string :type, null: false
      t.boolean :enabled, null: false, default: true
      t.json :settings, null: false, default: {}
      t.text :secret
      t.timestamps
      t.index :type, unique: true
    end

    # What was said, and when. A test alert has no monitor.
    create_table :alerts do |t|
      t.references :monitor, foreign_key: { to_table: :uptime_monitors }
      t.string :kind, null: false
      t.string :title, null: false
      t.text :message
      t.timestamps
      t.index :created_at
    end

    # Every attempt to send an alert through a channel, sent or failed.
    create_table :alert_deliveries do |t|
      t.references :alert, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: { to_table: :alert_channels }
      t.string :status, null: false
      t.text :error
      t.integer :attempt, null: false, default: 1
      t.datetime :attempted_at, null: false
      t.index [ :channel_id, :attempted_at ]
    end

    # The open outage: set when a monitor goes down, cleared when it recovers.
    # Unknown doesn't end it, so down → unknown → down alerts once.
    add_column :uptime_monitors, :outage_started_at, :datetime
    add_column :uptime_monitors, :reminded_at, :datetime
  end
end
