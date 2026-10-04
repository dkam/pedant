# When the check scheduler last ran. If it stopped for longer than GAP,
# Pedant (or its job worker) was down, and pushes sent meanwhile were lost:
# that's Pedant's outage, not the jobs' (ADR 0012).
class Uptime::Clock < ApplicationRecord
  GAP = 2.minutes

  # Records this tick and returns when the one before it was, or nil if
  # there's never been one.
  def self.tick!(now = Time.current)
    clock = first_or_initialize
    previous = clock.ticked_at
    clock.update!(ticked_at: now)
    previous
  end

  def self.gap_before?(previous, now = Time.current)
    previous.present? && previous < now - GAP
  end
end
