module PedantMcp
  class ListMonitors < MCP::Tool
    tool_name "list_monitors"
    description "Every monitor with its state, since when, and how many outages it had in the last 24 hours " \
      "and 7 days (one still going counts). Down first, then unknown, warn and pending, then up. counts covers every active monitor, " \
      "whatever the filters. Retired monitors (removed from monitors.yml) are left out unless asked for."
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        state: { type: "string", enum: Uptime::Monitor::STATES, description: "Only monitors in this state." },
        kind: { type: "string", enum: Uptime::Monitor::KINDS, description: "Only this kind: http, tcp or push." },
        include_retired: { type: "boolean", description: "Include monitors removed from monitors.yml. Default false." }
      }
    )

    def self.call(state: nil, kind: nil, include_retired: false, server_context: nil)
      PedantMcp.ok(Readout::Monitors.new(state: state, kind: kind, include_retired: include_retired == true).to_h)
    end
  end
end
