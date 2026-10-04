require "test_helper"

class Uptime::HttpCheckTest < ActiveSupport::TestCase
  URL = "http://splat.local:3030/up"

  test "a 2xx answer is up, with how long it took" do
    stub_request(:get, URL).to_return(status: 200)

    result = check

    assert_equal "up", result.status
    assert_kind_of Integer, result.latency_ms
    assert_nil result.message
  end

  test "an error status is down, and says which" do
    stub_request(:get, URL).to_return(status: 503)

    result = check

    assert_equal "down", result.status
    assert_equal "HTTP 503", result.message
  end

  test "redirects are followed to the answer" do
    stub_request(:get, URL).to_return(status: 301, headers: { "Location" => "/login" })
    stub_request(:get, "http://splat.local:3030/login").to_return(status: 200)

    assert_equal "up", check.status
  end

  test "too many redirects is down" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => URL })

    result = check

    assert_equal "down", result.status
    assert_match(/redirects/i, result.message)
  end

  test "expect_status widens what counts as up" do
    stub_request(:get, URL).to_return(status: 401)

    assert_equal "down", check.status
    assert_equal "up", check("expect_status" => "200-299, 401").status
  end

  test "a timeout is down, and says how long it waited" do
    stub_request(:get, URL).to_timeout

    result = check

    assert_equal "down", result.status
    assert_equal "Timed out after 10s", result.message
  end

  test "a refused connection is down" do
    stub_request(:get, URL).to_raise(Errno::ECONNREFUSED)

    result = check

    assert_equal "down", result.status
    assert_equal "Connection refused", result.message
  end

  test "a TLS failure is down" do
    stub_request(:get, "https://splat.local/").to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))

    result = Uptime::HttpCheck.new(target: "https://splat.local/", timeout: 10, options: {}).call

    assert_equal "down", result.status
    assert_match(/TLS.*certificate verify failed/, result.message)
  end

  test "expect_body is up when the body contains it" do
    stub_request(:get, URL).to_return(status: 200, body: "# HELP tuber_jobs_ready\ntuber_jobs_ready 3\n")

    assert_equal "up", check("expect_body" => "tuber_").status
  end

  test "expect_body is down when the body doesn't contain it" do
    stub_request(:get, URL).to_return(status: 200, body: "<html>Bad gateway</html>")

    result = check("expect_body" => "tuber_")

    assert_equal "down", result.status
    assert_equal %(Body doesn't contain "tuber_"), result.message
  end

  test "a body check isn't reached when the status is already wrong" do
    stub_request(:get, URL).to_return(status: 502, body: "tuber_")

    assert_equal "HTTP 502", check("expect_body" => "tuber_").message
  end

  test "expect_json is up when every path has its value" do
    stub_request(:get, URL).to_return(status: 200, body: { queue_status: "healthy", queues: { fetch: { paused: false } }, workers: [ { alive: true } ] }.to_json)

    assert_equal "up", check("expect_json" => { "queue_status" => "healthy", "queues.fetch.paused" => false, "workers.0.alive" => true }).status
  end

  test "expect_json is down with what was found instead" do
    stub_request(:get, URL).to_return(status: 200, body: { queue_status: "degraded" }.to_json)

    result = check("expect_json" => { "queue_status" => "healthy" })

    assert_equal "down", result.status
    assert_equal %(queue_status is "degraded", expected "healthy"), result.message
  end

  test "expect_json is down when a path is missing" do
    stub_request(:get, URL).to_return(status: 200, body: { queues: {} }.to_json)

    assert_equal "queues.fetch.paused is missing", check("expect_json" => { "queues.fetch.paused" => false }).message
  end

  test "expect_json is down when the body isn't JSON" do
    stub_request(:get, URL).to_return(status: 200, body: "<html>Bad gateway</html>")

    result = check("expect_json" => { "queue_status" => "healthy" })

    assert_equal "down", result.status
    assert_equal "Body isn't JSON", result.message
  end

  test "a body too large to check is down rather than read without end" do
    stub_request(:get, URL).to_return(status: 200, body: "x" * (Uptime::HttpCheck::MAX_BODY + 1))

    result = check("expect_body" => "tuber_")

    assert_equal "down", result.status
    assert_match(/larger than 1 MB/, result.message)
  end

  test "the request says it's Pedant" do
    stub_request(:get, URL).with(headers: { "User-Agent" => "Pedant/#{Pedant::VERSION}" }).to_return(status: 200)

    assert_equal "up", check.status
  end

  private
    def check(options = {})
      Uptime::HttpCheck.new(target: URL, timeout: 10, options: { "expect_status" => "200-299", "tls_verify" => true }.merge(options)).call
    end
end
