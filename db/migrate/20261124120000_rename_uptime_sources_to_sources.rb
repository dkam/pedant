# A source serves deployments as well as monitors (ADR 0030), so it leaves the
# uptime namespace.
class RenameUptimeSourcesToSources < ActiveRecord::Migration[8.1]
  def change
    rename_table :uptime_sources, :sources
  end
end
