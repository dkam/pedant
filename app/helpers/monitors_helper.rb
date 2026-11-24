module MonitorsHelper
  # What a monitor watches, in a line: the URL, or how often a push is expected.
  def monitor_target(monitor)
    if monitor.push?
      last = monitor.last_pushed_at ? "last #{time_ago_in_words(monitor.last_pushed_at)} ago" : "none yet"
      expected = monitor.scheduled? ? "on #{monitor.schedule_in_words}" : "every #{seconds_in_words(monitor.interval)}"
      "Push, expected #{expected} (#{last})"
    else
      monitor.target
    end
  end

  # "the tailnet or 192.0.2.7": where a push monitor takes pushes from (ADR 0027).
  def push_sources_in_words(monitor)
    monitor.push_sources.map { |source| source == "tailnet" ? "the tailnet" : source }
      .to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  # "2 down · 1 hidden · 30 up": hidden ones are down, but counted apart.
  def dashboard_counts(counts, hidden:)
    counts = counts.dup
    counts["down"] -= hidden if hidden.positive?
    counts = counts.flat_map { |state, count| state == "down" ? [ [ state, count ], [ "hidden", hidden ] ] : [ [ state, count ] ] }
    counts.reject { |_state, count| count.zero? }.map { |state, count| "#{count} #{state}" }.join(" · ")
  end

  # "for about 18 hours more, or until its next push" (ADR 0033).
  def hidden_in_words(monitor)
    words = "for #{distance_of_time_in_words(Time.current, monitor.hidden_until)} more"
    monitor.hidden_until_next_push ? "#{words}, or until its next push" : words
  end

  def seconds_in_words(seconds)
    ActiveSupport::Duration.build(seconds).inspect
  end
end
