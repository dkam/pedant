require "test_helper"

# When a pushed value will reach a level, from its trend (ADR 0023).
class Uptime::ForecastTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 4, 12, 0)

  test "free space falling steadily reaches zero when the line says" do
    # 1 GB an hour, 76 GB left now.
    points = samples(hours: 24) { |hours_ago| 76 + hours_ago }

    assert_in_delta 76.hours, forecast(points, reaches: 0), 1.hour
  end

  test "a value rising towards its level works too, such as percent used towards 100" do
    points = samples(hours: 24) { |hours_ago| 60 - hours_ago * 0.5 }

    assert_in_delta 80.hours, forecast(points, reaches: 100), 1.hour
  end

  test "a trend heading away from the level is no forecast" do
    assert_nil forecast(samples(hours: 24) { |hours_ago| 50 - hours_ago }, reaches: 0)
  end

  test "a flat value is no forecast" do
    assert_nil forecast(samples(hours: 24) { 50 }, reaches: 0)
  end

  test "fewer than 6 hourly values is no forecast yet" do
    assert_nil forecast(samples(hours: 4) { |hours_ago| 10 + hours_ago }, reaches: 0)
  end

  test "a cleanup starts the fit again, so the slope before it is forgotten" do
    # Falling 2 GB an hour for 3 days, then a prune freed 100 GB, and it's
    # been flat for the 12 hours since.
    points = samples(hours: 84) { |hours_ago| hours_ago > 12 ? 20 + (hours_ago - 12) * 2 : 120 }

    assert_nil forecast(points, reaches: 0)
  end

  test "after a cleanup, only the slope since counts" do
    # Fast fall before the prune; 0.5 GB an hour since, 100 GB left.
    points = samples(hours: 84) { |hours_ago| hours_ago > 24 ? 20 + (hours_ago - 24) * 3 : 100 + hours_ago * 0.5 }

    assert_in_delta 200.hours, forecast(points, reaches: 0), 4.hours
  end

  test "a dip that recovers, like a nightly backup, doesn't restart the fit" do
    # 0.25 GB an hour over a week, with a 40 GB dip for 10 minutes each night.
    points = samples(hours: 168) do |hours_ago, minute|
      level = 50 + hours_ago * 0.25
      hours_ago % 24 == 2 && minute < 10 ? level - 40 : level
    end

    assert_in_delta 200.hours, forecast(points, reaches: 0), 20.hours
  end

  test "a dip happening right now barely moves the forecast" do
    points = samples(hours: 24) { |hours_ago| 76 + hours_ago }
    points[-1] = [ NOW, 36.0 ]

    assert_in_delta 76.hours, forecast(points, reaches: 0), 6.hours
  end

  test "the sooner of the day and the week wins, so a change of pace shows quickly" do
    # 0.1 GB an hour for six days, then 2 GB an hour over the last day.
    points = samples(hours: 168) { |hours_ago| hours_ago > 24 ? 52 + (hours_ago - 24) * 0.1 : 4 + hours_ago * 2 }

    assert_in_delta 2.hours, forecast(points, reaches: 0), 1.hour
  end

  test "values older than the week are ignored" do
    # A steep fall long ago, flat for the last week.
    points = samples(hours: 300) { |hours_ago| hours_ago > 200 ? 50 + (hours_ago - 200) * 5 : 50 }

    assert_nil forecast(points, reaches: 0)
  end

  test "already past the level is no time left" do
    assert_equal 0, forecast(samples(hours: 24) { |hours_ago| -2 + hours_ago * 0.1 }, reaches: 0)
  end

  private
    # A sample every 5 minutes for the given hours, oldest first, ending now.
    # The block gets whole hours ago and the minute within that hour.
    def samples(hours:)
      (hours * 12).downto(0).map do |step|
        minutes_ago = step * 5
        [ NOW - minutes_ago.minutes, yield(minutes_ago / 60, 55 - minutes_ago % 60).to_f ]
      end
    end

    def forecast(points, reaches:)
      Uptime::Forecast.new(points, reaches: reaches, now: NOW).time_left
    end
end
