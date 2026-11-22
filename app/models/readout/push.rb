# What a push monitor expects and what it last heard (ADRs 0018, 0019, 0023):
# for push_monitors and monitor_history over MCP.
class Readout::Push
  LIMITS = %w[ warn_above warn_below down_above down_below ].freeze

  def initialize(monitor, now: Time.current)
    @monitor = monitor
    @now = now
  end

  def to_h
    {
      expected: expected,
      grace_seconds: @monitor.grace,
      max_runtime_seconds: @monitor.max_runtime,
      # Addresses, ranges, or "tailnet" (ADR 0027).
      pushes_from: @monitor.push_sources,
      last_pushed_at: Readout.iso(@monitor.last_pushed_at),
      silent_for_seconds: ((@now - @monitor.last_pushed_at).round if @monitor.last_pushed_at),
      # The scheduler looks again then: if no push has come by that time, it's
      # missed. Past it, the monitor is already down.
      missed_after: Readout.iso(@monitor.next_check_at),
      running_since: Readout.iso(@monitor.started_at),
      value: value
    }
  end

  private
    def expected
      if @monitor.scheduled?
        { schedule: @monitor.options["schedule"], timezone: @monitor.options["timezone"] }
      else
        { every_seconds: @monitor.interval }
      end
    end

    def value
      settings = @monitor.value_settings
      return if settings.empty?

      {
        label: settings["label"],
        unit: settings["unit"],
        last: @monitor.last_value,
        shown: @monitor.format_value(@monitor.last_value),
        limits: settings.slice(*LIMITS),
        forecast: (forecast(settings["forecast"]) if @monitor.forecast?)
      }
    end

    def forecast(settings)
      time_left = @monitor.forecast_time_left
      {
        reaches: settings["reaches"],
        down_within_seconds: settings["down_within"],
        warn_within_seconds: settings["warn_within"],
        # nil while it isn't heading there, or has fewer than 6 hours of values.
        reaches_in_seconds: time_left,
        summary: @monitor.forecast_in_words(time_left)
      }
    end
end
