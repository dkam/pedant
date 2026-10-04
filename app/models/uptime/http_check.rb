require "net/http"

# One HTTP check: GET the target, follow redirects, and compare the final
# status with what the monitor expects. With expect_body or expect_json, the
# body of a good answer is checked too (Kuma's keyword and json-query monitors).
class Uptime::HttpCheck
  MAX_REDIRECTS = 5
  # Only read when a body check needs it, and never past this.
  MAX_BODY = 1.megabyte

  def initialize(target:, timeout:, options:)
    @target = target
    @timeout = timeout
    @expect = parse_expected(options.fetch("expect_status", "200-299"))
    @tls_verify = options.fetch("tls_verify", true)
    @expect_body = options["expect_body"]
    @expect_json = options["expect_json"]
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response, body = fetch(URI(@target))
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    status = response.code.to_i

    problem = if @expect.none? { |range| range.cover?(status) }
      "HTTP #{status}"
    else
      body_problem(body)
    end

    Uptime::Result.new(status: problem ? "down" : "up", latency_ms: latency_ms, message: problem)
  rescue BodyTooLarge
    down "Body larger than #{MAX_BODY / 1.megabyte} MB"
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
    class BodyTooLarge < StandardError; end

    # The final response, and its body if a body check needs it.
    def fetch(uri, redirects = 0)
      body = nil
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          verify_mode: @tls_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
          open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout, ssl_timeout: @timeout) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "Pedant/#{Pedant::VERSION}")) do |response|
          body = read_body(response) if @expect_body || @expect_json
        end
      end

      return [ response, body ] unless response.is_a?(Net::HTTPRedirection) && response["Location"].present?
      raise TooManyRedirects if redirects >= MAX_REDIRECTS

      fetch(uri.merge(response["Location"]), redirects + 1)
    end

    # Reads the body in chunks, giving up past MAX_BODY.
    def read_body(response)
      body = +""
      response.read_body do |chunk|
        body << chunk
        raise BodyTooLarge if body.bytesize > MAX_BODY
      end
      body
    end

    def body_problem(body)
      if @expect_body && !body.to_s.b.include?(@expect_body.b)
        "Body doesn't contain #{@expect_body.inspect}"
      elsif @expect_json
        json_problem(body)
      end
    end

    # The first path whose value isn't the expected one, if any. A path is
    # keys and array indexes joined with dots: workers.0.alive.
    def json_problem(body)
      document = JSON.parse(body.to_s)
      @expect_json.each do |path, expected|
        found = path.split(".").reduce([ document ]) do |(node), step|
          if node.is_a?(Hash) && node.key?(step) then [ node[step] ]
          elsif node.is_a?(Array) && step.match?(/\A\d+\z/) && step.to_i < node.size then [ node[step.to_i] ]
          else break nil
          end
        end
        return "#{path} is missing" if found.nil?
        return "#{path} is #{found.first.to_json}, expected #{expected.to_json}" unless found.first == expected
      end
      nil
    rescue JSON::ParserError
      "Body isn't JSON"
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
