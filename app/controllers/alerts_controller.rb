# The alerts page: ntfy and email settings, and what was sent lately.
class AlertsController < ApplicationController
  def index
    @channels = AlertChannel::KINDS.keys.to_h { |kind| [ kind, AlertChannel.for(kind) ] }
    @alerts = Alert.includes(:monitor, deliveries: :channel).order(created_at: :desc, id: :desc).limit(50)
  end
end
