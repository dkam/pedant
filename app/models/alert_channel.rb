# Where alerts go: ntfy and email (ADR 0013). Pedant's own configuration,
# entered on the alerts page, with its one secret (the ntfy token or the SMTP
# password) encrypted and never shown again.
#
# deliver records every attempt, sent or failed, and raises DeliveryFailed on
# failure so DeliverAlertJob retries.
class AlertChannel < ApplicationRecord
  class DeliveryFailed < StandardError; end

  KINDS = { "ntfy" => "AlertChannel::Ntfy", "email" => "AlertChannel::Email" }.freeze
  TIMEOUT = 10

  encrypts :secret
  has_many :deliveries, class_name: "AlertDelivery", foreign_key: :channel_id, dependent: :delete_all

  scope :enabled, -> { where(enabled: true) }

  def self.for(kind) = KINDS.fetch(kind).constantize.first_or_initialize

  def deliver(alert, attempt: 1)
    send_alert(alert)
    deliveries.create!(alert: alert, status: "sent", attempt: attempt, attempted_at: Time.current)
  rescue DeliveryFailed, StandardError => error
    message = error.is_a?(DeliveryFailed) ? error.message : "#{error.class.name.demodulize}: #{error.message}"
    deliveries.create!(alert: alert, status: "failed", error: message.truncate(500), attempt: attempt, attempted_at: Time.current)
    raise DeliveryFailed, message
  end

  def latest_delivery = deliveries.order(:attempted_at, :id).last
  def failing? = latest_delivery&.status == "failed"

  # Back to the monitor in Pedant, from the address the settings were saved at.
  def link_for(alert)
    "#{settings["link_base"]}/monitors/#{alert.monitor_id}" if alert.monitor_id && settings["link_base"].present?
  end
end
