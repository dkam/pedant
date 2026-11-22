# One monitor's history: its page, and monitor_history over MCP. State changes
# are kept for good; checks for Uptime::Check::RETENTION.
class Readout::History
  CHART_POINTS = 100

  attr_reader :monitor

  # checks and state_changes: how many of each, newest first. hours: only
  # those within the last so many hours.
  def initialize(monitor, checks: 50, state_changes: 20, hours: nil, now: Time.current)
    @monitor = monitor
    @check_limit = checks
    @state_change_limit = state_changes
    @since = now - hours.hours if hours
    @now = now
  end

  def checks
    @checks ||= within(@monitor.checks, :checked_at).order(checked_at: :desc, id: :desc).limit(@check_limit).to_a
  end

  def state_changes
    @state_changes ||= within(@monitor.state_changes, :changed_at).order(changed_at: :desc, id: :desc).limit(@state_change_limit).to_a
  end

  # Oldest first, for the charts on the monitor's page.
  def chart_checks
    @monitor.checks.order(checked_at: :desc, id: :desc).limit(CHART_POINTS).reverse
  end

  def to_h
    {
      monitor: Readout.monitor(@monitor, flaps: Readout.flaps_for([ @monitor ], now: @now).fetch(@monitor.id)).merge(definition),
      state_changes: state_changes.map { |change| state_change(change) },
      checks: checks.map { |check| check(check) }
    }
  end

  private
    def within(scope, column)
      @since ? scope.where(column => @since..) : scope
    end

    # How it's checked, from monitors.yml.
    def definition
      if @monitor.push?
        { push: Readout::Push.new(@monitor, now: @now).to_h }
      else
        { interval_seconds: @monitor.interval, timeout_seconds: @monitor.timeout }
      end
    end

    def state_change(change)
      { from: change.from_state, to: change.to_state, at: Readout.iso(change.changed_at), message: change.message }
    end

    def check(check)
      {
        status: check.status,
        at: Readout.iso(check.checked_at),
        message: check.message,
        latency_ms: check.latency_ms,
        value: check.value,
        duration_ms: check.duration_ms
      }
    end
end
