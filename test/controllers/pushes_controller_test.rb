require "test_helper"

# Kuma's push URL shape (ADR 0012): /api/push/<token>?status=up|down&msg=…&ping=…
class PushesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # The limiter's counts live in the process and outlast a test; other tests
    # push with the same token.
    PushesController::RATE_LIMITS.clear
    @token, digest = push_token
    @source = monitor_source("monitors.yml" => { "nas-backup" => { "push" => digest, "interval" => 3600 } })
    @source.sync!
    @monitor = @source.monitors.sole
    # Pushes come over the tailnet unless a test says otherwise (ADR 0027).
    integration_session.remote_addr = TAILNET_ADDRESS
  end

  test "a push with no status is up, as in Kuma, and needs no login" do
    get "/api/push/#{@token}"

    assert_response :success
    assert_equal({ "ok" => true }, response.parsed_body)
    assert_equal "up", @monitor.reload.state
  end

  test "the message and ping are kept with the check" do
    get "/api/push/#{@token}", params: { status: "up", msg: "OK", ping: "123.4" }

    check = @monitor.checks.sole
    assert_equal [ "up", "OK", 123 ], [ check.status, check.message, check.latency_ms ]
  end

  test "a push resets the clock: missed only after interval plus grace from now" do
    freeze_time do
      get "/api/push/#{@token}"

      assert_equal (3600 + 60).seconds.from_now, @monitor.reload.next_check_at
    end
  end

  test "status=down is down straight away, and anything but up counts as down, as in Kuma" do
    get "/api/push/#{@token}", params: { status: "down", msg: "backup failed" }

    @monitor.reload
    assert_equal "down", @monitor.state
    assert_equal "backup failed", @monitor.last_message

    get "/api/push/#{@token}", params: { status: "up" }
    get "/api/push/#{@token}", params: { status: "bogus" }
    assert_equal "down", @monitor.reload.state
  end

  test "a push or a run's start doesn't refresh the dashboards; the scheduler's next tick does (#10)" do
    assert_turbo_stream_broadcasts(:monitors, count: 0) do
      get "/api/push/#{@token}", params: { status: "start" }
      get "/api/push/#{@token}"
    end
  end

  test "POST works as well as GET" do
    post "/api/push/#{@token}", params: { status: "up" }

    assert_response :success
    assert_equal "up", @monitor.reload.state
  end

  test "an unknown token is a 404, in Kuma's shape" do
    get "/api/push/not-a-token"

    assert_response :not_found
    assert_equal false, response.parsed_body["ok"]
  end

  test "a retired monitor's token is a 404" do
    @monitor.update!(retired_at: Time.current)

    get "/api/push/#{@token}"

    assert_response :not_found
    assert_empty @monitor.checks
  end

  # Sync never gives an http monitor a digest as its target; this is the
  # lookup's second line of defence if a row ever had one.
  test "an http monitor can't be pushed to, even if its target were a push digest" do
    token, digest = push_token("token-for-an-http-monitor")
    http = monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://splat.local/" } } }, "other").tap(&:sync!).monitors.sole
    http.update_columns(target: digest)

    get "/api/push/#{token}"

    assert_response :not_found
    assert_empty http.checks
  end

  test "each token is rate limited" do
    30.times { get "/api/push/#{@token}" }
    get "/api/push/#{@token}"

    assert_response :too_many_requests
    assert_equal 30, @monitor.checks.count
  end

  # Which addresses may push (ADR 0027). In production every push comes
  # through Caddy and then Thruster (see push_through_proxies).
  test "without from:, a push is taken from the tailnet, over IPv4 or IPv6" do
    push_through_proxies from: "100.101.102.103"
    assert_response :success

    push_through_proxies from: "fd7a:115c:a1e0::1"
    assert_response :success
    assert_equal 2, @monitor.checks.count
  end

  test "without from:, a push from outside the tailnet is a 404, the same as an unknown token" do
    push_through_proxies from: "203.0.113.5"

    assert_response :not_found
    assert_equal({ "ok" => false, "msg" => "Monitor not found or not active." }, response.parsed_body)
    assert_empty @monitor.checks
  end

  test "from: takes pushes from its addresses only, and not from the tailnet" do
    resync("from" => "203.0.113.5")

    push_through_proxies from: "203.0.113.5"
    assert_response :success

    push_through_proxies from: "203.0.113.6"
    assert_response :not_found

    push_through_proxies from: "100.101.102.103"
    assert_response :not_found
    assert_equal 1, @monitor.checks.count
  end

  test "from: can name ranges, and tailnet alongside other addresses" do
    resync("from" => [ "tailnet", "198.51.100.0/24", "2001:db8::/32" ])

    [ "100.101.102.103", "198.51.100.77", "2001:db8::5" ].each do |address|
      push_through_proxies from: address
      assert_response :success, "expected a push from #{address} to be taken"
    end

    push_through_proxies from: "198.51.101.1"
    assert_response :not_found
  end

  test "an IPv4 address written as IPv6 is the same address" do
    resync("from" => "203.0.113.5")

    push_through_proxies from: "::ffff:203.0.113.5"

    assert_response :success
  end

  test "a forged Client-IP header doesn't get a push in" do
    push_through_proxies from: "203.0.113.5", headers: { "Client-Ip" => "100.101.102.103" }

    assert_response :not_found
    assert_empty @monitor.checks
  end

  # If a proxy appends to the client's own X-Forwarded-For, the last address
  # is the one the proxy saw.
  test "a forged address ahead of the proxy's in X-Forwarded-For doesn't get a push in" do
    push_through_proxies from: "100.101.102.103, 203.0.113.5"

    assert_response :not_found
    assert_empty @monitor.checks
  end

  # Tailscale's IPv6 addresses are in fc00::/7, which Rails trusts as proxies
  # by default, so a forged Client-IP behind one would have been believed.
  test "a tailnet address over IPv6 can't claim another address with Client-IP" do
    resync("from" => "203.0.113.5")

    push_through_proxies from: "fd7a:115c:a1e0::1", headers: { "Client-Ip" => "203.0.113.5" }

    assert_response :not_found
    assert_empty @monitor.checks
  end

  test "pushes refused from elsewhere don't use up the token's rate limit" do
    31.times { push_through_proxies from: "203.0.113.5" }

    push_through_proxies from: "100.101.102.103"

    assert_response :success
  end

  test "the token never reaches the log" do
    log = StringIO.new
    with_logger(ActiveSupport::Logger.new(log)) do
      get "/api/push/#{@token}", params: { status: "up", msg: "OK" }
      get "/api/push/not-a-real-token-either"
    end

    assert_response :not_found
    assert_includes log.string, "/api/push/"
    assert_not_includes log.string, @token
    assert_not_includes log.string, "not-a-real-token-either"
  end

  private
    # As on grab01: Caddy sets X-Forwarded-For to the client, Thruster in the
    # container appends Docker's gateway, and Puma sees Thruster on 127.0.0.1.
    def push_through_proxies(from:, headers: {})
      get "/api/push/#{@token}", headers: { "X-Forwarded-For" => "#{from}, 172.18.0.1" }.merge(headers), env: { "REMOTE_ADDR" => "127.0.0.1" }
    end

    def resync(settings)
      write_monitor_files(@source.path, "monitors.yml" => { "nas-backup" => { "push" => push_token.last, "interval" => 3600 }.merge(settings) })
      @source.sync!
      assert_empty @source.sync_error_list
    end

    def with_logger(logger)
      previous = [ Rails.logger, ActionController::Base.logger ]
      Rails.logger = ActionController::Base.logger = logger
      yield
    ensure
      Rails.logger, ActionController::Base.logger = previous
    end
end
