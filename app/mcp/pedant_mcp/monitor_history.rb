module PedantMcp
  class MonitorHistory < MCP::Tool
    MAX_CHECKS = 500
    MAX_STATE_CHANGES = 200

    tool_name "monitor_history"
    description "One monitor: how it's checked, its state changes and its recent checks, newest first. " \
      "State changes are kept for good; checks for #{Uptime::Check::RETENTION.inspect}. " \
      "A push monitor also gets what push_monitors gives."
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        monitor: { type: "string", description: "The monitor's key in monitors.yml (as list_monitors gives it), or its id." },
        checks: PedantMcp.integer_arg("How many checks, newest first. Default 50, at most #{MAX_CHECKS}."),
        state_changes: PedantMcp.integer_arg("How many state changes, newest first. Default 20, at most #{MAX_STATE_CHANGES}."),
        hours: PedantMcp.integer_arg("Only checks and state changes within the last so many hours.")
      },
      required: %w[ monitor ]
    )

    def self.call(monitor:, checks: nil, state_changes: nil, hours: nil, server_context: nil)
      readout = Readout::History.new(PedantMcp.monitor(monitor),
        checks: PedantMcp.whole_number(checks, default: 50, range: 0..MAX_CHECKS),
        state_changes: PedantMcp.whole_number(state_changes, default: 20, range: 0..MAX_STATE_CHANGES),
        hours: (PedantMcp.whole_number(hours, default: nil, range: 1..(24 * 365)) if hours))
      PedantMcp.ok(readout.to_h)
    rescue ToolError => error
      PedantMcp.error(error.message)
    end
  end
end
