# When a pushed value will reach a level, from its trend (ADR 0023): free
# space reaching 0, or percent used reaching 100.
#
# Each window (the last day, the last week) is fitted separately, and the
# sooner answer wins. Within a window:
#
# - Values are taken as the median of each hour, counted back from now, so a
#   dip shorter than half an hour doesn't move the line at all.
# - The fit starts again after a cleanup: an hour further from the level than
#   every hour in the RESTART_LOOKBACK before it, by more than RESTART_JUMP of
#   its distance. A dip that recovers only gets back to where it was, so it
#   doesn't restart the fit.
# - The time left is read off the fitted line, not the latest value.
class Uptime::Forecast
  WINDOWS = [ 1.day, 7.days ].freeze
  MIN_HOURS = 6
  RESTART_LOOKBACK = 6
  RESTART_JUMP = 0.1

  # points: [time, value] pairs, oldest first.
  def initialize(points, reaches:, now: Time.current)
    @now = now
    @reaches = reaches.to_f
    @hours = hourly_medians(points.select { |time, _| time > now - WINDOWS.max })
  end

  # Seconds until the trend reaches the level, 0 if it already has, or nil if
  # it isn't heading there (or there's too little to say).
  def time_left
    return if @hours.empty?

    # Which way is "towards": free space falls to 0, percent used rises to 100.
    @falling = @hours.first.last > @reaches
    WINDOWS.filter_map { |window| time_left_within(window) }.min
  end

  private
    def time_left_within(window)
      hours = @hours.select { |time, _| time > @now - window }
      hours = hours.drop(last_restart(hours))
      return if hours.size < MIN_HOURS

      slope, intercept = fit(hours)
      at_now = intercept + slope * @now.to_f
      return 0 if distance(at_now) <= 0
      return unless @falling ? slope.negative? : slope.positive?

      ((@reaches - at_now) / slope).round
    end

    # How far a value is from the level, on the side it started.
    def distance(value)
      @falling ? value - @reaches : @reaches - value
    end

    def last_restart(hours)
      hours.each_index.reverse_each.find(-> { 0 }) do |index|
        before = hours[[ index - RESTART_LOOKBACK, 0 ].max...index].map { |_, value| distance(value) }
        before.any? && distance(hours[index].last) - before.max > RESTART_JUMP * distance(hours[index].last)
      end
    end

    # Oldest first: [mean time, median value] for each hour back from now.
    def hourly_medians(points)
      points.group_by { |time, _| ((@now - time) / 3600).floor }.sort_by { |hours_ago, _| -hours_ago }.map do |_, hour|
        values = hour.map(&:last).sort
        middle = values.size / 2
        median = values.size.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2
        [ Time.at(hour.sum { |time, _| time.to_f } / hour.size), median ]
      end
    end

    # Least squares: value = intercept + slope * seconds.
    def fit(points)
      xs = points.map { |time, _| time.to_f }
      ys = points.map(&:last)
      x_mean = xs.sum / xs.size
      y_mean = ys.sum / ys.size
      slope = xs.zip(ys).sum { |x, y| (x - x_mean) * (y - y_mean) } / xs.sum { |x| (x - x_mean)**2 }
      [ slope, y_mean - slope * x_mean ]
    end
end
