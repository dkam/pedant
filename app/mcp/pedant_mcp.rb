# Pedant's read-only MCP server (ADR 0025), served at POST /mcp by
# McpController with an API token. Agents ask "is it up, has it flapped, did
# the push arrive" without a shell on the host.
#
# The tools hold no logic: each reads through a Readout (app/models/readout),
# which the HTML views share, and returns its hash as JSON. Every tool is
# read-only; changes are PRs against the stacks repo (ADRs 0001, 0002, 0016).
module PedantMcp
  # An expected failure the caller can act on, answered as a tool error.
  class ToolError < StandardError; end

  module_function

  def server
    MCP::Server.new(
      name: "pedant",
      title: "Pedant",
      version: Pedant::VERSION,
      tools: [ ListMonitors, MonitorHistory, PushMonitors, RecentAlerts, About ],
      configuration: MCP::Configuration.new(exception_reporter: method(:report_exception)),
      instructions: <<~TEXT
        Pedant watches Booko's services: HTTP and TCP checks on a schedule, and
        push monitors that jobs call when they run. This server only reads.
        Monitors are defined in monitors.yml files in the stacks repos, so any
        change to a monitor is a pull request there, not a call here.

        States: up; down (failures in a row passed its retries, or a push was
        missed or reported down); warn (a pushed value is past a warn limit, or
        forecast to reach its level soon); pending (no conclusive result yet);
        unknown (Pedant's own connection was down, so it couldn't tell; never
        alerted). "Flapping" is how often it went down: down_in_24h and
        down_in_7d.

        Start with list_monitors. monitor_history shows one monitor's state
        changes and checks. push_monitors shows when each push monitor last
        checked in and when it will count as missed. recent_alerts shows what
        was sent, and whether each channel delivered it.
        about says which Pedant this is and what it runs on, down to each gem's
        version, for checking an advisory against it.

        Times are UTC, in ISO 8601.
      TEXT
    )
  end

  def ok(payload)
    MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
  end

  def error(message)
    MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
  end

  # A whole number from an argument, kept within range. Clients send "20" as
  # often as 20; the schemas accept both.
  def whole_number(value, default:, range:)
    number = case value
    when nil then return default
    when Integer then value
    # A base, so "010" is 10 rather than octal; Integer() refuses a base for
    # anything but a string.
    when String then Integer(value, 10)
    end
    raise ToolError, "#{value.inspect} isn't a whole number." unless number

    number.clamp(range)
  rescue ArgumentError
    raise ToolError, "#{value.inspect} isn't a whole number."
  end

  def monitor(reference)
    Readout.find_monitor(reference)
  rescue Readout::NotFound => error
    raise ToolError, error.message
  end

  # The schema of a whole-number argument. Strings of digits are accepted too,
  # since clients send them.
  def integer_arg(description)
    { type: %w[ integer string ], pattern: "^[0-9]+$", description: description }
  end

  # The gem answers an exception escaping a tool with an opaque "Internal
  # error calling tool …", so internals don't reach the client, and hands it
  # here. The caller's own mistakes (an unknown tool, bad params) arrive too,
  # and are answered already.
  def report_exception(exception, _context = nil)
    return if exception.is_a?(MCP::Server::RequestHandlerError) && exception.error_type != :internal_error

    original = exception.try(:original_error) || exception
    Rails.logger.error("MCP tool error: #{original.class}: #{original.message}")
  end
end
