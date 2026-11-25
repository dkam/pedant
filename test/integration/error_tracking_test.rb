require "test_helper"
require "sentry/test_helper"

# Pedant's own errors go to Splat over the Sentry protocol (ADR 0035), when
# SENTRY_DSN is set. What goes must carry no credential: not a push token, an
# API token, a session or the owner's address. And the sites Pedant checks
# must hear nothing from it: no trace headers, whose baggage names the release.
class ErrorTrackingTest < ActionDispatch::IntegrationTest
  include Sentry::TestHelper

  setup do
    Sentry.init do |config|
      Pedant::ErrorTracking.configure(config, dsn: Sentry::TestHelper::DUMMY_DSN)
      config.background_worker_threads = 0
    end
    setup_sentry_test
  end

  teardown do
    teardown_sentry_test
    Sentry.close
  end

  test "an error in a push is sent with the controller's name, never the token" do
    # Made here, so the token can't turn up in this file's own lines, which
    # an event carries around each frame of its stack.
    token, digest = push_token(SecureRandom.hex(12))
    monitor_source("monitors.yml" => { "backup" => { "name" => "pg02 backup", "push" => digest, "interval" => "1d" } }).sync!
    integration_session.remote_addr = "100.101.102.103"

    raising(Uptime::Monitor, :active, "database is locked") do
      assert_raises(RuntimeError) { get "/api/push/#{token}?status=up&msg=OK" }
    end

    event = last_sentry_event
    assert_match "database is locked", event.exception.values.last.value
    assert_not_includes event.transaction, token
    assert_not_includes sent(event), token
  end

  test "an error on a page is sent without the session, any token or the owner's address" do
    create_password_owner
    sign_in_with_password
    session_cookie = cookies.to_hash.values.join(" ")
    api_token = SecureRandom.hex(12)
    address = "203.0.113.#{rand(2..254)}"

    raising(Readout::Monitors, :new, "the readout broke") do
      assert_raises(RuntimeError) do
        get root_url, headers: { "Authorization" => "Bearer #{api_token}", "X-Forwarded-For" => address }
      end
    end

    event = last_sentry_event
    assert_match "the readout broke", event.exception.values.last.value
    json = sent(event)
    assert_not_includes json, api_token
    assert_not_includes json, address
    assert_not_includes json, "dan@example.com"
    session_cookie.split.each { |value| assert_not_includes json, value }
  end

  # A real server, because Sentry adds its headers in Net::HTTP itself, which
  # a WebMock stub never reaches.
  test "a check sends the site no trace headers" do
    server = TCPServer.new("127.0.0.1", 0)
    received = Thread.new do
      client = server.accept
      lines = []
      while (line = client.gets) && line != "\r\n"
        lines << line
      end
      client.write "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      client.close
      lines
    end

    result = Uptime::HttpCheck.new(target: "http://127.0.0.1:#{server.addr[1]}/up", timeout: 5, options: {}).call

    assert_equal "up", result.status
    names = received.join(5)&.value.to_a.drop(1).map { |line| line.split(":", 2).first.downcase }
    assert_includes names, "user-agent"
    assert_empty names & %w[ sentry-trace baggage traceparent ]
  ensure
    server&.close
  end

  test "the release names the version and the revision" do
    assert_equal "#{Pedant::VERSION}+#{Rails.application.config.x.revision}", Sentry.configuration.release
  end

  private
    # The event as it would be sent.
    def sent(event) = JSON.generate(event.to_json_compatible)

    # Makes object.name raise for the block, then puts back what was there.
    def raising(object, name, message)
      singleton = object.singleton_class
      original = singleton.instance_method(name) if singleton.method_defined?(name, false) || singleton.private_method_defined?(name, false)
      singleton.define_method(name) { |*, **| raise message }
      yield
    ensure
      singleton.remove_method(name)
      singleton.define_method(name, original) if original
    end
end
