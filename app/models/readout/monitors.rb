# The monitor list: the dashboard, and list_monitors over MCP. Down first,
# then unknown, warn and pending, then hidden (down, but the owner knows; ADR
# 0033), then up.
class Readout::Monitors
  ORDER = %w[ down unknown warn pending hidden up ].freeze

  def initialize(state: nil, kind: nil, include_retired: false, now: Time.current)
    @state = state.presence
    @kind = kind.presence
    @include_retired = include_retired
    @now = now
  end

  def monitors
    @monitors ||= begin
      scope = Uptime::Monitor.by_urgency.includes(:source)
      scope = scope.active unless @include_retired
      scope = scope.where(state: @state) if @state
      scope = scope.where(kind: @kind) if @kind
      scope.to_a.sort_by.with_index { |monitor, index| [ ORDER.index(monitor.hidden?(@now) ? "hidden" : monitor.state), index ] }
    end
  end

  # How many times a monitor went down in the last 24 hours.
  def flaps(monitor) = flap_counts.fetch(monitor.id)[:day]

  # Active monitors in each state, whatever the filters: the whole picture.
  def counts
    @counts ||= begin
      counts = Uptime::Monitor.active.group(:state).count
      %w[ down unknown warn pending up ].filter_map { |state| [ state, counts[state] ] if counts[state] }.to_h
    end
  end

  # Active monitors hidden while down. counts still has them as down.
  def hidden
    @hidden ||= Uptime::Monitor.active.where(state: "down").where("hidden_until > ?", @now).count
  end

  def to_h
    {
      counts: counts,
      monitors: monitors.map { |monitor| Readout.monitor(monitor, flaps: flap_counts.fetch(monitor.id)) }
    }
  end

  private
    def flap_counts
      @flap_counts ||= Readout.flaps_for(monitors, now: @now)
    end
end
