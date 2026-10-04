# Saving a channel, and sending a test through it (ADR 0013). The secret is
# never shown again; a blank one keeps what's saved.
class AlertChannelsController < ApplicationController
  FIELDS = { "ntfy" => %i[ url secret enabled ], "email" => %i[ address port user_name secret from to enabled ] }.freeze

  before_action :set_channel

  def update
    attributes = params.expect(alert_channel: FIELDS.fetch(params[:kind]))
    attributes.delete(:secret) if attributes[:secret].blank?
    @channel.assign_attributes(attributes)
    @channel.settings = @channel.settings.merge("link_base" => request.base_url)

    if @channel.save
      redirect_to alerts_path, notice: "#{@channel.kind_name} saved."
    else
      @channels = AlertChannel::KINDS.keys.to_h { |kind| [ kind, kind == params[:kind] ? @channel : AlertChannel.for(kind) ] }
      @alerts = Alert.includes(:monitor, deliveries: :channel).order(created_at: :desc, id: :desc).limit(50)
      render "alerts/index", status: :unprocessable_content
    end
  end

  def test
    return redirect_to(alerts_path, alert: "Save #{@channel.kind_name} before testing it.") if @channel.new_record?

    alert = Alert.create!(kind: "test", title: "Test alert from Pedant", message: "If you can read this, #{@channel.kind_name} alerts work.")
    @channel.deliver(alert)
    redirect_to alerts_path, notice: "Test alert sent through #{@channel.kind_name}."
  rescue AlertChannel::DeliveryFailed => error
    redirect_to alerts_path, alert: "#{@channel.kind_name} failed: #{error.message}"
  end

  private
    def set_channel
      return head(:not_found) unless AlertChannel::KINDS.key?(params[:kind])
      @channel = AlertChannel.for(params[:kind])
    end
end
