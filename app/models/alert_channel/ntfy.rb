require "net/http"

# A POST to an ntfy topic, in the shape splat's notifier uses: the message as
# the body, and Title, Priority, Tags, Click and an optional bearer token.
class AlertChannel::Ntfy < AlertChannel
  STYLE = {
    "down" => [ "high", "red_circle" ],
    "reminder" => [ "high", "red_circle" ],
    "recovered" => [ "default", "green_circle" ],
    "test" => [ "default", "test_tube" ]
  }.freeze

  store_accessor :settings, :url

  validate :url_is_a_topic

  def kind_name = "ntfy"

  private
    def send_alert(alert)
      uri = URI(url)
      priority, tags = STYLE.fetch(alert.kind)
      request = Net::HTTP::Post.new(uri, "Content-Type" => "text/plain; charset=utf-8", "Title" => alert.title,
        "Priority" => priority, "Tags" => tags)
      request["Click"] = link_for(alert) if link_for(alert)
      request["Authorization"] = "Bearer #{secret}" if secret.present?
      request.body = alert.message.to_s

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end
      raise DeliveryFailed, "HTTP #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise DeliveryFailed, "Timed out after #{TIMEOUT}s"
    end

    def url_is_a_topic
      uri = URI.parse(url.to_s)
      errors.add(:url, "must be an http:// or https:// topic URL, like https://ntfy.sh/your-topic") unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.path.to_s.length > 1
    rescue URI::InvalidURIError
      errors.add(:url, "isn't a URL")
    end
end
