# One result, kept for the monitor's history. Pruned after RETENTION; the
# state changes, which say when it went down and for how long, are kept.
class Uptime::Check < ApplicationRecord
  RETENTION = 14.days

  belongs_to :monitor

  def self.prune
    where(checked_at: ...RETENTION.ago).in_batches(of: 5_000).delete_all
  end
end
