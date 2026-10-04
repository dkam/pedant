module MonitorsHelper
  # What a monitor watches, in a line: the URL, or how often a push is expected.
  def monitor_target(monitor)
    if monitor.push?
      last = monitor.last_pushed_at ? "last #{time_ago_in_words(monitor.last_pushed_at)} ago" : "none yet"
      "Push, expected every #{seconds_in_words(monitor.interval)} (#{last})"
    else
      monitor.target
    end
  end

  def seconds_in_words(seconds)
    ActiveSupport::Duration.build(seconds).inspect
  end
end
