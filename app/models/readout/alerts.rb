# What Pedant told someone, and whether it got there: the alerts page, and
# recent_alerts over MCP. A channel is named only by its kind. Its settings
# and secret never appear, and they're taken out of delivery errors too, in
# case a server echoed them back.
class Readout::Alerts
  FILTERED = "[FILTERED]"

  # monitor: an Uptime::Monitor. kind: one of Alert::KINDS. hours: only
  # alerts within the last so many hours.
  def initialize(limit: 50, monitor: nil, kind: nil, hours: nil, now: Time.current)
    @limit = limit
    @monitor = monitor
    @kind = kind.presence
    @since = now - hours.hours if hours
  end

  # Newest first.
  def alerts
    @alerts ||= begin
      scope = Alert.includes(:monitor, deliveries: :channel).order(created_at: :desc, id: :desc).limit(@limit)
      scope = scope.where(monitor: @monitor) if @monitor
      scope = scope.where(kind: @kind) if @kind
      scope = scope.where(created_at: @since..) if @since
      scope.to_a
    end
  end

  def channels
    @channels ||= AlertChannel.order(:type).to_a
  end

  def to_h
    {
      channels: channels.map { |channel| channel_status(channel) },
      alerts: alerts.map { |alert| alert(alert) }
    }
  end

  private
    def channel_status(channel)
      latest = channel.latest_delivery
      {
        channel: channel.kind_name,
        enabled: channel.enabled,
        failing: latest&.status == "failed",
        last_delivery: (delivery(latest) if latest)
      }
    end

    def alert(alert)
      {
        id: alert.id,
        kind: alert.kind,
        title: alert.title,
        message: alert.message,
        created_at: Readout.iso(alert.created_at),
        monitor: (alert.monitor && { id: alert.monitor.id, key: alert.monitor.key, name: alert.monitor.name }),
        deliveries: alert.deliveries.sort_by { |delivery| [ delivery.attempted_at, delivery.id ] }.map { |delivery| delivery(delivery) }
      }
    end

    def delivery(delivery)
      {
        channel: delivery.channel.kind_name,
        status: delivery.status,
        attempt: delivery.attempt,
        attempted_at: Readout.iso(delivery.attempted_at),
        error: redact(delivery.error, delivery.channel)
      }
    end

    def redact(text, channel)
      return text if text.blank?

      secrets_of(channel).reduce(text) { |redacted, secret| redacted.gsub(secret, FILTERED) }
    end

    # Longest first, so the whole URL goes before the host and path within it.
    def secrets_of(channel)
      secrets = [ channel.secret ]
      if (url = channel.settings["url"]).present?
        secrets += [ url, host_and_path(url) ]
      end
      secrets.compact_blank.uniq.sort_by { |secret| -secret.length }
    end

    def host_and_path(url)
      uri = URI.parse(url)
      "#{uri.host}#{uri.path}" if uri.host
    rescue URI::InvalidURIError
      nil
    end
end
