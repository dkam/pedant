require "test_helper"

# The tools, called directly. They hold no logic of their own, so this checks
# that each hands its arguments to its readout, and turns a caller's mistake
# into a tool error they can read. A direct call skips the schema validation
# the transport does (test/integration/mcp_endpoint_test.rb), so the tools'
# own guards are tested here.
class PedantMcpTest < ActiveSupport::TestCase
  setup do
    _token, digest = push_token
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "nas-backup" => { "push" => digest, "interval" => "1h" }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @push = @source.monitors.find_by!(key: "nas-backup")
    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
  end

  test "every tool is read-only" do
    PedantMcp.server.tools.each_value do |tool|
      annotations = tool.annotations_value.to_h
      assert_equal true, annotations[:readOnlyHint], tool.name_value
      assert_equal false, annotations[:destructiveHint], tool.name_value
    end
  end

  test "list_monitors is the monitor readout" do
    json = call(PedantMcp::ListMonitors, state: "down")

    assert_equal JSON.parse(Readout::Monitors.new(state: "down").to_h.to_json), json
  end

  test "monitor_history is the history readout" do
    json = call(PedantMcp::MonitorHistory, monitor: "splat", checks: "1", state_changes: 1, hours: "24")

    assert_equal "splat", json.dig("monitor", "key")
    assert_equal 1, json["checks"].size
    assert_equal 1, json["state_changes"].size
  end

  test "counts out of range are kept in range" do
    json = call(PedantMcp::MonitorHistory, monitor: "splat", checks: "100000")

    assert_equal 1, json["checks"].size
  end

  test "a count that isn't a whole number is a tool error" do
    response = PedantMcp::MonitorHistory.call(monitor: "splat", checks: "lots")

    assert response.error?
    assert_match "lots", response.content.first[:text]
  end

  test "push_monitors lists push monitors only, or the one named" do
    assert_equal [ "nas-backup" ], call(PedantMcp::PushMonitors)["monitors"].map { |monitor| monitor["key"] }
    assert_equal [ "nas-backup" ], call(PedantMcp::PushMonitors, monitor: @push.id.to_s)["monitors"].map { |monitor| monitor["key"] }
    assert_equal [], call(PedantMcp::PushMonitors, state: "down")["monitors"]
  end

  test "push_monitors refuses a monitor that isn't a push monitor" do
    response = PedantMcp::PushMonitors.call(monitor: "splat")

    assert response.error?
    assert_match "http monitor, not a push monitor", response.content.first[:text]
  end

  test "recent_alerts filters by monitor and kind" do
    json = call(PedantMcp::RecentAlerts, monitor: "splat", kind: "down", limit: "5", hours: "1")

    assert_equal [ "Splat is down" ], json["alerts"].map { |alert| alert["title"] }
  end

  test "a monitor that doesn't exist is a tool error" do
    [ PedantMcp::MonitorHistory, PedantMcp::PushMonitors, PedantMcp::RecentAlerts ].each do |tool|
      response = tool.call(monitor: "nope")

      assert response.error?, tool.name_value
      assert_match "nope", response.content.first[:text]
    end
  end

  test "an unexpected failure is logged, without the caller's mistakes" do
    log = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    PedantMcp.report_exception(MCP::Server::RequestHandlerError.new("Tool not found: x", {}, error_type: :invalid_params))
    assert_empty log.string

    PedantMcp.report_exception(MCP::Server::RequestHandlerError.new("Internal error", {}, original_error: RuntimeError.new("boom")))
    assert_match "RuntimeError: boom", log.string
  ensure
    Rails.logger = previous
  end

  private
    def call(tool, **arguments)
      response = tool.call(**arguments)
      assert_not response.error?, response.content.first[:text]
      JSON.parse(response.content.first[:text])
    end
end
