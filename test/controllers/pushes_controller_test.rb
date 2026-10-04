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

  test "an http monitor can't be pushed to, even by its target" do
    http = monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://splat.local/" } } }, "other").tap(&:sync!).monitors.sole

    get "/api/push/#{CGI.escape(http.target)}"

    assert_response :not_found
  end

  test "each token is rate limited" do
    30.times { get "/api/push/#{@token}" }
    get "/api/push/#{@token}"

    assert_response :too_many_requests
    assert_equal 30, @monitor.checks.count
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
    def with_logger(logger)
      previous = [ Rails.logger, ActionController::Base.logger ]
      Rails.logger = ActionController::Base.logger = logger
      yield
    ensure
      Rails.logger, ActionController::Base.logger = previous
    end
end
