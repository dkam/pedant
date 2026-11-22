# Pedant's read side (ADR 0025): what the dashboard, a monitor's page and the
# alerts page show, as one query layer. A readout gives the HTML views records,
# and gives the MCP server (and a JSON API later) a hash.
#
# Every hash names its fields one by one; no record is serialised whole. A new
# column, or a secret, never reaches the output just by being added. In
# particular, nothing here returns an alert channel's secret or settings (the
# ntfy topic URL is effectively a password), a push monitor's target (its
# token's digest), or anything about sign-in.
module Readout
  # A reference that names no monitor, or more than one.
  class NotFound < StandardError; end

  module_function

  # A monitor by its key in monitors.yml, or by its id. Keys are unique within
  # a source but not across sources, so a key that two active monitors share
  # is refused, with their ids.
  def find_monitor(reference)
    reference = reference.to_s.strip
    raise NotFound, "Name a monitor by its key in monitors.yml, or its id." if reference.empty?

    matches = Uptime::Monitor.where(key: reference).includes(:source).to_a
    matches = matches.reject(&:retired?) if matches.many? && matches.any? { |monitor| !monitor.retired? }
    return matches.first if matches.one?

    if matches.many?
      raise NotFound, "#{reference.inspect} is the key of several monitors: " \
        "#{matches.map { |monitor| "id #{monitor.id} in #{monitor.source.name}" }.join(", ")}. Give the id instead."
    end

    by_id = Uptime::Monitor.includes(:source).find_by(id: reference) if reference.match?(/\A\d+\z/)
    by_id || raise(NotFound, "No monitor has the key or id #{reference.inspect}.")
  end

  # What a monitor is and how it is now. The same fields in every tool that
  # lists monitors. flaps: { day:, week: } counts of going down, worked out by
  # the caller for many monitors at once.
  def monitor(monitor, flaps:)
    {
      id: monitor.id,
      key: monitor.key,
      name: monitor.name,
      kind: monitor.kind,
      # A push monitor's target is its token's digest, and stays out.
      target: (monitor.target unless monitor.push?),
      defined_in: "#{monitor.source.name}: #{monitor.defined_in}",
      state: monitor.state,
      state_since: iso(monitor.state_changed_at),
      retired_at: iso(monitor.retired_at),
      outage_started_at: iso(monitor.outage_started_at),
      failures_in_a_row: monitor.consecutive_failures,
      retries: monitor.retries,
      down_in_24h: flaps.fetch(:day),
      down_in_7d: flaps.fetch(:week),
      last_checked_at: iso(monitor.last_checked_at),
      last_message: monitor.last_message,
      last_latency_ms: monitor.last_latency_ms,
      last_value: (monitor.format_value(monitor.last_value) if monitor.last_value),
      last_pushed_at: (iso(monitor.last_pushed_at) if monitor.push?)
    }
  end

  # How many times each monitor went down in the last day and week, in two
  # queries rather than two per monitor: the "how often does it flap" half of
  # the liveness model (Uptime::Monitor#flaps).
  def flaps_for(monitors, now: Time.current)
    ids = monitors.map(&:id)
    downs = Uptime::StateChange.where(monitor_id: ids, to_state: "down")
    day = downs.where(changed_at: (now - 24.hours)..).group(:monitor_id).count
    week = downs.where(changed_at: (now - 7.days)..).group(:monitor_id).count
    ids.index_with { |id| { day: day.fetch(id, 0), week: week.fetch(id, 0) } }
  end

  def iso(time) = time&.utc&.iso8601
end
