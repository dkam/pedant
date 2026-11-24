class Uptime::StateChange < ApplicationRecord
  belongs_to :monitor

  # The states that open or close an outage, as for alerts
  # (Uptime::Monitor::Outages): down opens one, up or warn closes it. Pending
  # and unknown do neither, so down → unknown → down is one outage.
  OUTAGE_STATES = %w[ up warn down ].freeze

  # How many outages each monitor had that overlap each window ending at now:
  # one already open when the window began, plus each one that opened in it
  # (ADR 0026). { monitor_id => [ count for each window ] }, in two queries
  # however many monitors.
  def self.outages_within(monitor_ids, windows, now: Time.current)
    starts = windows.map { |window| now - window }
    relevant = where(monitor_id: monitor_ids, to_state: OUTAGE_STATES)
    before = latest_by_monitor(relevant.where(changed_at: ...starts.min))
    since = relevant.where(changed_at: starts.min..).order(:changed_at, :id).pluck(:monitor_id, :to_state, :changed_at).group_by(&:first)

    monitor_ids.index_with do |id|
      changes = since.fetch(id, []).map { |_id, to_state, at| [ to_state, at ] }
      starts.map { |start| outages_from(start, open_before: before[id] == "down", changes: changes) }
    end
  end

  # Each monitor's newest change in scope: { monitor_id => to_state }. The
  # subquery takes the table's own name so the outer columns resolve.
  def self.latest_by_monitor(scope)
    ranked = scope.select(:monitor_id, :to_state, "ROW_NUMBER() OVER (PARTITION BY monitor_id ORDER BY changed_at DESC, id DESC) AS place")
    unscoped.from(ranked, table_name).where("place = 1").pluck(:monitor_id, :to_state).to_h
  end

  # changes are [ to_state, changed_at ], oldest first, all OUTAGE_STATES.
  def self.outages_from(start, open_before:, changes:)
    earlier, within = changes.partition { |_to_state, at| at < start }
    open = earlier.any? ? earlier.last.first == "down" : open_before
    count = open ? 1 : 0

    within.each do |to_state, _at|
      count += 1 if to_state == "down" && !open
      open = to_state == "down"
    end
    count
  end
  private_class_method :latest_by_monitor, :outages_from
end
