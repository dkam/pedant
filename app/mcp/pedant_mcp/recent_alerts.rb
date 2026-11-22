module PedantMcp
  class RecentAlerts < MCP::Tool
    MAX = 200

    tool_name "recent_alerts"
    description "Alerts Pedant sent, newest first: a monitor going down, a reminder while it stays down, " \
      "its recovery, or a test. Each lists every delivery attempt per channel (ntfy, email) and whether it " \
      "was sent or failed. channels says whether each channel is enabled and how its last delivery went. " \
      "Unknown is never alerted."
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        limit: PedantMcp.integer_arg("How many alerts. Default 20, at most #{MAX}."),
        hours: PedantMcp.integer_arg("Only alerts within the last so many hours."),
        monitor: { type: "string", description: "Only this monitor's alerts: its key in monitors.yml, or its id." },
        kind: { type: "string", enum: Alert::KINDS, description: "Only alerts of this kind." }
      }
    )

    def self.call(limit: nil, hours: nil, monitor: nil, kind: nil, server_context: nil)
      readout = Readout::Alerts.new(
        limit: PedantMcp.whole_number(limit, default: 20, range: 1..MAX),
        hours: (PedantMcp.whole_number(hours, default: nil, range: 1..(24 * 365)) if hours),
        monitor: (PedantMcp.monitor(monitor) if monitor),
        kind: kind)
      PedantMcp.ok(readout.to_h)
    rescue ToolError => error
      PedantMcp.error(error.message)
    end
  end
end
