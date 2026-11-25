# Uptime checks (milestone 1, ADR 0004). Monitors are defined in git (ADR 0016);
# this namespace holds what Pedant observes about them.
#
# Namespaced because a top-level Monitor would collide with Ruby's own.
module Uptime
  def self.table_name_prefix = "uptime_"

  DAY_PARTS = { day: 86_400, hour: 3600, minute: 60, second: 1 }.freeze

  # "34 days, 1 hour, and 21 minutes": days at most, as monitors.yml writes
  # them. ActiveSupport's month (2,629,746 seconds) and year aren't whole
  # minutes, so a duration built with them showed stray seconds (#18).
  def self.duration_in_words(seconds)
    rest = seconds.to_i
    words = DAY_PARTS.filter_map do |unit, size|
      count, rest = rest.divmod(size)
      "#{count} #{unit.to_s.pluralize(count)}" if count.positive?
    end
    words.any? ? words.to_sentence(locale: false) : "0 seconds"
  end
end
