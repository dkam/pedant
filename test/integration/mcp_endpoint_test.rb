require "test_helper"

# POST /mcp, the read-only MCP server (ADR 0025): who gets in, the shapes an
# MCP client expects, and that no secret reaches any answer. The readouts
# behind the tools are tested in test/models/readout.
class McpEndpointTest < ActionDispatch::IntegrationTest
  OIDC_SECRET = "oidc-client-secret-for-mcp-tests"

  setup do
    # The refusal counts live in the process and outlast a test.
    McpController::REFUSALS.clear
    @push_token, push_digest = push_token("a-push-token-for-mcp-tests")
    @source = monitor_source("monitors.yml" => {
      "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "retries" => 0 },
      "nas-disk" => { "push" => push_digest, "interval" => "5m",
        "value" => { "label" => "Free on /", "unit" => "GB", "down_below" => 5,
          "forecast" => { "reaches" => 0, "down_within" => "3d", "warn_within" => "14d" } } }
    })
    @source.sync!
    @splat = @source.monitors.find_by!(key: "splat")
    @nas = @source.monitors.find_by!(key: "nas-disk")
    @push_digest = push_digest

    @ntfy = ntfy_channel!
    @email = email_channel!
    @email.update!(settings: @email.settings.merge("user_name" => "smtp-user-for-mcp-tests"))
    OidcProvider.create!(FakeOidcProvider.new.stub!.provider_attributes.merge(client_secret: OIDC_SECRET))
    create_password_owner

    @splat.record(Uptime::Result.new(status: "down", message: "HTTP 503"))
    @nas.record_push(@nas.push_result(status: "up", value: "42"))
    alert = Alert.where(monitor: @splat, kind: "down").sole
    # A server that echoes the topic URL and token back in its error.
    @ntfy.deliveries.create!(alert: alert, status: "failed", attempt: 1, attempted_at: Time.current,
      error: "HTTP 401: token ntfy-secret-token refused for #{AlertChannels::NTFY_URL}")
    @email.deliveries.create!(alert: alert, status: "sent", attempt: 1, attempted_at: Time.current)

    _record, @token = ApiToken.issue!(name: "laptop")
  end

  # --- Who gets in ----------------------------------------------------------

  test "no token is refused" do
    rpc "tools/list", token: nil

    assert_response :unauthorized
    assert_match(/\ABearer/, response.headers["WWW-Authenticate"])
    assert_equal(-32001, response.parsed_body.dig("error", "code"))
    assert_match "settings", response.parsed_body.dig("error", "message")
  end

  test "a wrong token is refused" do
    rpc "tools/list", token: "pedant_#{"x" * 43}"

    assert_response :unauthorized
  end

  test "a revoked token is refused" do
    ApiToken.destroy_all

    rpc "tools/list"

    assert_response :unauthorized
  end

  test "a push token is not an API token" do
    rpc "tools/list", token: @push_token

    assert_response :unauthorized
  end

  test "a signed-in browser without a token is refused" do
    sign_in_with_password

    rpc "tools/list", token: nil

    assert_response :unauthorized
  end

  test "a token that's refused calls no tool" do
    rpc "tools/call", { name: "list_monitors", arguments: {} }, token: "wrong"

    assert_response :unauthorized
    assert_nil response.parsed_body["result"]
  end

  # /mcp is on the internet (ADR 0025). Guessing a token is hopeless, but an
  # address that keeps trying is cut off for a while, good token or not.
  test "an address with too many refused requests is turned away for a while" do
    McpController::MAX_REFUSALS.times { rpc "tools/list", token: "wrong", from: "203.0.113.9" }
    assert_response :unauthorized

    rpc "tools/list", from: "203.0.113.9"

    assert_response :too_many_requests
    assert_equal(-32001, response.parsed_body.dig("error", "code"))
    assert_match "Too many", response.parsed_body.dig("error", "message")

    rpc "tools/list", from: "198.51.100.7"

    assert_response :success

    travel McpController::REFUSAL_WINDOW + 1.second do
      rpc "tools/list", from: "203.0.113.9"

      assert_response :success
    end
  end

  test "a good token doesn't count towards the limit" do
    (McpController::MAX_REFUSALS + 5).times { rpc "tools/list", from: "203.0.113.9" }

    assert_response :success
  end

  # --- Speaking MCP ---------------------------------------------------------

  test "initialize names the server and gives instructions" do
    rpc "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } }

    assert_response :success
    assert_equal "pedant", result.dig("serverInfo", "name")
    assert_equal Pedant::VERSION, result.dig("serverInfo", "version")
    assert_match "only reads", result["instructions"]
  end

  # The only tool without arguments, so the one a transport could trip over.
  test "about answers over the endpoint" do
    call_tool "about"

    assert_response :success
    assert_not result["isError"], tool_text
    assert_equal Pedant::VERSION, tool_json.dig("pedant", "version")
  end

  test "tools/list offers the five tools, each marked read-only" do
    rpc "tools/list"

    tools = result.fetch("tools")
    assert_equal %w[ about list_monitors monitor_history push_monitors recent_alerts ], tools.map { |tool| tool["name"] }.sort
    tools.each do |tool|
      assert_equal true, tool.dig("annotations", "readOnlyHint"), tool["name"]
      assert_equal false, tool.dig("annotations", "destructiveHint"), tool["name"]
    end
  end

  test "list_monitors reads the monitors" do
    call_tool "list_monitors"

    assert_response :success
    assert_not result["isError"]
    assert_equal %w[ splat nas-disk ], tool_json.fetch("monitors").map { |monitor| monitor["key"] }
    assert_equal({ "down" => 1, "up" => 1 }, tool_json.fetch("counts"))
  end

  # Clients send counts as JSON numbers and as strings of digits; both work.
  test "a count can be a number or a string" do
    call_tool "monitor_history", monitor: "splat", checks: 5, state_changes: "5"

    assert_not result["isError"], tool_text
    assert_equal 1, tool_json.fetch("checks").size

    call_tool "recent_alerts", limit: 1

    assert_not result["isError"], tool_text
    assert_equal 1, tool_json.fetch("alerts").size
  end

  test "monitor_history reads one monitor" do
    call_tool "monitor_history", monitor: "splat", checks: "5"

    assert_equal "splat", tool_json.dig("monitor", "key")
    assert_equal [ "down" ], tool_json.fetch("checks").map { |check| check["status"] }
  end

  test "push_monitors reads the push monitors" do
    call_tool "push_monitors"

    assert_equal [ "nas-disk" ], tool_json.fetch("monitors").map { |monitor| monitor["key"] }
    assert_equal "42 GB", tool_json.dig("monitors", 0, "push", "value", "shown")
  end

  test "recent_alerts reads the alerts and their deliveries" do
    call_tool "recent_alerts"

    alert = tool_json.fetch("alerts").first
    assert_equal "Splat is down", alert["title"]
    assert_equal %w[ ntfy email ], alert["deliveries"].map { |delivery| delivery["channel"] }
  end

  test "a monitor that doesn't exist is a tool error the caller can read" do
    call_tool "monitor_history", monitor: "nope"

    assert_response :success
    assert result["isError"]
    assert_match "nope", tool_text
  end

  test "a bad argument is a tool error, not a protocol error" do
    call_tool "list_monitors", state: "sideways"

    assert result["isError"]
  end

  test "a notification is accepted with nothing to say" do
    post mcp_path, params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: headers_for(@token)

    assert_response :accepted
    assert_empty response.body
  end

  test "a frame that isn't JSON is a parse error" do
    post mcp_path, params: "{nope", headers: headers_for(@token)

    assert_equal(-32700, response.parsed_body.dig("error", "code"))
  end

  test "GET and DELETE are not offered" do
    get mcp_path, headers: headers_for(@token)

    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]

    delete mcp_path, headers: headers_for(@token)

    assert_response :method_not_allowed
  end

  test "using a token notes when it was last used" do
    freeze_time do
      rpc "tools/list"

      assert_equal Time.current, ApiToken.sole.last_used_at
    end
  end

  # --- What never comes back -------------------------------------------------

  test "no secret appears in any answer" do
    answers = []
    rpc "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } }
    answers << response.body
    rpc "tools/list"
    answers << response.body
    [
      [ "list_monitors", {} ],
      [ "list_monitors", { include_retired: true } ],
      [ "monitor_history", { monitor: "splat" } ],
      [ "monitor_history", { monitor: "nas-disk" } ],
      [ "push_monitors", {} ],
      [ "push_monitors", { monitor: "nas-disk" } ],
      [ "recent_alerts", {} ],
      [ "recent_alerts", { monitor: "splat" } ]
    ].each do |name, arguments|
      call_tool name, **arguments
      assert_not result["isError"], "#{name} #{arguments}: #{tool_text}"
      answers << response.body
    end

    secrets = {
      "the ntfy token" => "ntfy-secret-token",
      "the ntfy topic URL" => AlertChannels::NTFY_URL,
      "the ntfy topic" => "ntfy.example.test/pedant",
      "the SMTP password" => "smtp-password",
      "the SMTP server" => "smtp.example.test",
      "the SMTP user" => "smtp-user-for-mcp-tests",
      "the OIDC client secret" => OIDC_SECRET,
      "the owner's email" => "dan@example.com",
      "the push token" => @push_token,
      "the push token's digest" => @push_digest.delete_prefix("sha256:"),
      "the API token" => @token,
      "the API token's digest" => ApiToken.sole.token_digest
    }
    answers.each do |answer|
      secrets.each { |what, secret| assert_not_includes answer, secret, "#{what} leaked" }
    end
    assert answers.any? { |answer| answer.include?("[FILTERED]") }, "the delivery error is shown, redacted"
  end

  test "the token never reaches the log" do
    log = StringIO.new
    with_logger(ActiveSupport::Logger.new(log)) do
      call_tool "list_monitors"
      rpc "tools/list", token: "pedant_a-wrong-token-for-the-log-test"
    end

    assert_includes log.string, "/mcp"
    assert_not_includes log.string, @token
    assert_not_includes log.string, "a-wrong-token-for-the-log-test"
  end

  private
    def rpc(method, params = nil, token: @token, from: "127.0.0.1")
      frame = { jsonrpc: "2.0", id: 1, method: method, params: params }.compact
      post mcp_path, params: frame.to_json, headers: headers_for(token), env: { "REMOTE_ADDR" => from }
    end

    def call_tool(name, **arguments)
      rpc "tools/call", { name: name, arguments: arguments }
    end

    def headers_for(token)
      headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
      headers["Authorization"] = "Bearer #{token}" if token
      headers
    end

    def result = response.parsed_body.fetch("result")
    def tool_text = result.dig("content", 0, "text")
    def tool_json = JSON.parse(tool_text)

    def with_logger(logger)
      previous = [ Rails.logger, ActionController::Base.logger ]
      Rails.logger = ActionController::Base.logger = logger
      yield
    ensure
      Rails.logger, ActionController::Base.logger = previous
    end
end
