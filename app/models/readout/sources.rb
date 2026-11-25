# The monitor sources (ADRs 0016, 0030): which repos Pedant reads, and how
# each one's last sync went. The settings page's source list, and list_sources
# over MCP, which tells a source never added from one whose checkout is empty
# or whose monitors.yml doesn't parse, without a browser.
#
# A source's path is the owner's own setting and holds no secret. Its sync
# errors name files, keys and fields, never a push token or its digest.
class Readout::Sources
  def sources
    @sources ||= Source.order(:name).to_a
  end

  # How many of a source's monitors are in its files now, and how many were
  # removed from them (retired).
  def monitors(source) = monitor_counts.fetch([ source.id, true ], 0)
  def retired_monitors(source) = monitor_counts.fetch([ source.id, false ], 0)

  def to_h
    {
      sources: sources.map do |source|
        {
          id: source.id,
          name: source.name,
          path: source.path,
          # Sources sync every minute, so an old one means the sync isn't running.
          synced_at: Readout.iso(source.synced_at),
          # Both nil when the path isn't a git checkout: say, an empty
          # directory Docker made for a mount before the clone existed.
          commit_sha: source.commit_sha,
          dirty: source.dirty,
          sync_errors: source.sync_error_list,
          monitors: monitors(source),
          retired_monitors: retired_monitors(source)
        }
      end
    }
  end

  private
    # { [source_id, active?] => count }, in one query for every source.
    def monitor_counts
      @monitor_counts ||= Uptime::Monitor.where(source_id: sources.map(&:id))
        .group(:source_id, Arel.sql("retired_at IS NULL")).count
        .transform_keys { |source_id, active| [ source_id, ActiveModel::Type::Boolean.new.cast(active) ] }
    end
end
