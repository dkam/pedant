# What a push monitor does beyond up and down (ADR 0019):
#
# - A value (value=87), judged against the limits monitors.yml gives it. The
#   limits live in git, never in the push, so a script can't loosen its own.
#   A forecast judges where the value is heading too (ADR 0023).
# - Runs: status=start, then the finish. The duration is kept, and a run
#   longer than max_runtime is down without waiting for the interval.
# - A cron schedule in place of an interval, so days off aren't missed.
module Uptime::Monitor::Push
  extend ActiveSupport::Concern

  # Turns a push's parameters into a result. The job's own down wins; then
  # the down limits, the forecast's down_within, the warn limits, and the
  # forecast's warn_within.
  def push_result(status:, value: nil, message: nil, latency_ms: nil)
    number = Float(value) if value.present?
    return Uptime::Result.new(status: "down", message: message || "Job reported down", value: number, latency_ms: latency_ms) if status == "down"

    judged_status, limit_message = judge(number)
    Uptime::Result.new(status: judged_status, message: limit_message || message, value: number, latency_ms: latency_ms)
  rescue ArgumentError
    Uptime::Result.new(status: "down", message: "Pushed value #{value.to_s.truncate(40).inspect} isn't a number", latency_ms: latency_ms)
  end

  # A push arrived. A push monitor has no retries: the job said how it went.
  # If a run was started, this is its finish.
  def record_push(result)
    now = Time.current
    if started_at
      result = result.with(duration_ms: ((now - started_at) * 1000).round)
      self.started_at = nil
    end
    self.last_pushed_at = now
    record(result)
  end

  # status=start. With a max_runtime, the run must finish by then.
  def start_run!(now = Time.current)
    self.started_at = now
    self.next_check_at = [ next_check_at, now + max_runtime ].compact.min if max_runtime
    save!
  end

  def next_push_due_from(time)
    due = (scheduled? ? next_scheduled_after(time) : time + interval) + grace
    due = [ due, started_at + max_runtime ].min if started_at && max_runtime
    due
  end

  def scheduled? = options["schedule"].present?
  def max_runtime = options["max_runtime"]
  def value_settings = options["value"] || {}

  def schedule_in_words
    "#{options["schedule"]} (#{options["timezone"]})" if scheduled?
  end

  def forecast? = value_settings["forecast"].is_a?(Hash)

  # Seconds until the pushed values reach the forecast's level (ADR 0023), or
  # nil if they aren't heading there. A number given is counted as pushed now.
  def forecast_time_left(number = nil)
    now = Time.current
    points = checks.where(checked_at: (now - Uptime::Forecast::WINDOWS.max)..).where.not(value: nil).order(:checked_at).pluck(:checked_at, :value)
    points << [ now, number ] if number
    Uptime::Forecast.new(points, reaches: value_settings["forecast"]["reaches"], now: now).time_left
  end

  def forecast_in_words
    reaches = format_value(value_settings["forecast"]["reaches"].to_f)
    time_left = forecast_time_left
    time_left ? "Reaches #{reaches} in about #{roughly(time_left)}" : "Not heading for #{reaches}"
  end

  def format_value(number)
    return if number.nil?
    shown = number % 1 == 0 ? number.to_i : number
    unit = value_settings["unit"]
    unit.blank? ? shown.to_s : (unit == "%" ? "#{shown}%" : "#{shown} #{unit}")
  end

  private
    def missed_push
      if started_at && max_runtime && Time.current >= started_at + max_runtime
        Uptime::Result.new(status: "down", message: "Started #{to_the_minute(Time.current - started_at).inspect} ago, still running")
      else
        Uptime::Result.new(status: "down", message: "No push for #{to_the_minute(Time.current - (last_pushed_at || created_at)).inspect}")
      end
    end

    def judge(number)
      return [ "up", nil ] if number.nil?

      limits = value_settings
      forecast = limits["forecast"]
      time_left = forecast_time_left(number) if forecast
      { "down" => %w[ down_above down_below ], "warn" => %w[ warn_above warn_below ] }.each do |status, (above, below)|
        return [ status, limit_message(number, "over", limits[above]) ] if limits[above] && number > limits[above]
        return [ status, limit_message(number, "under", limits[below]) ] if limits[below] && number < limits[below]

        within = forecast && forecast["#{status}_within"]
        return [ status, forecast_message(number, time_left) ] if time_left && within && time_left <= within
      end
      [ "up", nil ]
    end

    def forecast_message(number, time_left)
      "#{value_settings["label"].presence || "Value"} #{format_value(number)}, reaches #{format_value(value_settings["forecast"]["reaches"].to_f)} in about #{roughly(time_left)}"
    end

    # Days once it's a day or more, then hours, then minutes.
    def roughly(seconds)
      name, size = { "day" => 1.day, "hour" => 1.hour, "minute" => 1.minute }.find { |_, size| seconds >= size } || [ "minute", 1.minute ]
      count = [ (seconds / size.to_f).round, 1 ].max
      "#{count} #{name.pluralize(count)}"
    end

    def limit_message(number, direction, limit)
      "#{value_settings["label"].presence || "Value"} #{format_value(number)} (#{direction} #{format_value(limit.to_f)})"
    end

    def next_scheduled_after(time)
      Fugit.parse_cron("#{options["schedule"]} #{options["timezone"]}").next_time(time).to_t
    end
end
