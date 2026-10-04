# Re-reads every source's monitors.yml files (ADR 0016). Every minute.
class Uptime::SyncSourcesJob < ApplicationJob
  def perform
    Uptime::Source.find_each(&:sync!)
  end
end
