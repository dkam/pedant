# Email through the SMTP server entered on the alerts page, independent of
# ntfy: if ntfy is down with the fleet, email still gets through (ADR 0013).
class AlertChannel::Email < AlertChannel
  store_accessor :settings, :address, :port, :user_name, :from, :to

  validates :address, :from, :to, presence: true
  validates :port, numericality: { only_integer: true, in: 1..65_535 }
  validate :addresses_are_emails

  def kind_name = "email"

  def port = super.presence&.to_i
  def port=(value)
    super(value.presence&.to_i)
  end
  def recipients = to.to_s.split(",").map(&:strip).reject(&:blank?)

  def smtp_settings
    {
      address: address, port: port, user_name: user_name.presence, password: secret.presence,
      authentication: (:plain if user_name.present?), enable_starttls_auto: true,
      open_timeout: TIMEOUT, read_timeout: TIMEOUT
    }.compact
  end

  private
    def send_alert(alert)
      AlertMailer.with(alert: alert, channel: self).alert.deliver_now
    end

    def addresses_are_emails
      errors.add(:from, "isn't an email address") if from.present? && !from.match?(URI::MailTo::EMAIL_REGEXP)
      bad = recipients.reject { |recipient| recipient.match?(URI::MailTo::EMAIL_REGEXP) }
      errors.add(:to, "has addresses that aren't: #{bad.join(", ")}") if bad.any?
    end
end
