module PedantMcp
  class ListSources < MCP::Tool
    tool_name "list_sources"
    description "The repos Pedant reads monitors.yml from, each with its path, when it last synced (every minute), " \
      "the commit its checkout is at and whether it has local changes, why the last sync went wrong if it did, " \
      "and how many monitors came from it, active and retired. commit_sha and dirty are null when the path isn't " \
      "a git checkout, such as an empty directory. A monitor that's missing: is its repo here, synced, at a recent " \
      "commit, without errors?"
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(server_context: nil)
      PedantMcp.ok(Readout::Sources.new.to_h)
    end
  end
end
