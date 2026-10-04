require "net/http"

# One HTTP check: GET the target, follow redirects, and compare the final
# status with what the monitor expects.
class Uptime::HttpCheck
  MAX_REDIRECTS = 5

  def initialize(target:, timeout:, options:)
    @target = target
    @timeout = timeout
    @expect = parse_expected(options.fetch("expect_status", "200-299"))
    @tls_verify = options.fetch("tls_verify", true)
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = fetch(URI(@target))
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    status = response.code.to_i

    if @expect.any? { |range| range.cover?(status) }
      Uptime::Result.new(status: "up", latency_ms: latency_ms)
    else
      Uptime::Result.new(status: "down", latency_ms: latency_ms, message: "HTTP #{status}")
    end
  rescue TooManyRedirects
    down "More than #{MAX_REDIRECTS} redirects"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    down "Timed out after #{@timeout}s"
  rescue Errno::ECONNREFUSED
    down "Connection refused"
  rescue OpenSSL::SSL::SSLError => error
    down "TLS: #{error.message}"
  rescue SocketError, SystemCallError, IOError, Net::HTTPBadResponse, URI::Error => error
    down error.message.presence || error.class.name
  end

  private
    class TooManyRedirects < StandardError; end

    def fetch(uri, redirects = 0)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          verify_mode: @tls_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
          open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout, ssl_timeout: @timeout) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "Pedant/#{Pedant::VERSION}"))
      end

      return response unless response.is_a?(Net::HTTPRedirection) && response["Location"].present?
      raise TooManyRedirects if redirects >= MAX_REDIRECTS

      fetch(uri.merge(response["Location"]), redirects + 1)
    end

    def down(message)
      Uptime::Result.new(status: "down", message: message)
    end

    # "200-299, 401" → [200..299, 401..401]
    def parse_expected(spec)
      spec.to_s.split(",").map do |part|
        low, high = part.strip.split("-", 2).map { |n| Integer(n) }
        low..(high || low)
      end
    end
end
