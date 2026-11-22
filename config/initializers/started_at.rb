# frozen_string_literal: true

# When this process booted, so "did the deploy restart it?" has an answer
# without a shell on the host (Readout::About). Puma forks its workers after
# boot, so this is the app's start, not a worker's.
Rails.application.config.x.started_at = Time.now.utc
