module PedantMcp
  class PushMonitors < MCP::Tool
    tool_name "push_monitors"
    description "Push monitors: when each last checked in and how long it's been silent, what it expects " \
      "(an interval or a cron schedule, plus grace), when silence will count as missed (missed_after), " \
      "a run in progress, its pushed value with limits and forecast, and which addresses it takes pushes from " \
      "(pushes_from: tailnet unless monitors.yml says; a push from elsewhere is a 404). Down first. " \
      "Use it to watch a job's first check-ins after moving it to Pedant."
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        monitor: { type: "string", description: "Just this push monitor: its key in monitors.yml, or its id." },
        state: { type: "string", enum: Uptime::Monitor::STATES, description: "Only push monitors in this state." }
      }
    )

    def self.call(monitor: nil, state: nil, server_context: nil)
      monitors = if monitor
        found = PedantMcp.monitor(monitor)
        raise ToolError, "#{found.key} is a #{found.kind} monitor, not a push monitor." unless found.push?
        [ found ]
      else
        Readout::Monitors.new(kind: "push", state: state).monitors
      end

      flaps = Readout.flaps_for(monitors)
      PedantMcp.ok(
        monitors: monitors.map do |push|
          Readout.monitor(push, flaps: flaps.fetch(push.id)).merge(push: Readout::Push.new(push).to_h)
        end
      )
    rescue ToolError => error
      PedantMcp.error(error.message)
    end
  end
end
