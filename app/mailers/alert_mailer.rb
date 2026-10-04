class AlertMailer < ApplicationMailer
  # Sent through the channel's own SMTP server, not a global one.
  def alert
    @alert = params[:alert]
    channel = params[:channel]
    @link = channel.link_for(@alert)

    mail(to: channel.recipients, from: channel.from, subject: @alert.title, delivery_method_options: channel.smtp_settings)
  end
end
