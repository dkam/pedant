class CreateUptime < ActiveRecord::Migration[8.1]
  def change
    # Where monitors.yml files are read from (ADR 0016). Pedant's own
    # configuration; the monitors themselves are in git.
    create_table :uptime_sources do |t|
      t.string :name, null: false
      t.string :path, null: false
      t.datetime :synced_at
      t.text :sync_errors
      t.timestamps
    end

    create_table :uptime_monitors do |t|
      t.references :source, null: false, foreign_key: { to_table: :uptime_sources }
      t.string :key, null: false

      # Copied from monitors.yml on every sync.
      t.string :name, null: false
      t.string :kind, null: false
      t.string :target, null: false
      t.integer :interval, null: false
      t.integer :timeout, null: false
      t.integer :retries, null: false
      t.json :options, null: false, default: {}
      t.string :defined_in, null: false
      t.datetime :retired_at

      # Observed.
      t.string :state, null: false, default: "pending"
      t.datetime :state_changed_at
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :last_checked_at
      t.datetime :next_check_at
      t.integer :last_latency_ms
      t.string :last_message

      t.timestamps
      t.index [ :source_id, :key ], unique: true
      t.index :next_check_at
    end

    create_table :uptime_checks do |t|
      t.references :monitor, null: false, foreign_key: { to_table: :uptime_monitors }, index: false
      t.string :status, null: false
      t.integer :latency_ms
      t.string :message
      t.datetime :checked_at, null: false
      t.index [ :monitor_id, :checked_at ]
      t.index :checked_at
    end

    create_table :uptime_state_changes do |t|
      t.references :monitor, null: false, foreign_key: { to_table: :uptime_monitors }, index: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :message
      t.datetime :changed_at, null: false
      t.index [ :monitor_id, :changed_at ]
    end
  end
end
