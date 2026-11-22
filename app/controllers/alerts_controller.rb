# The alerts page: ntfy and email settings, and what was sent lately.
class AlertsController < ApplicationController
  def index
    @channels = AlertChannel::KINDS.keys.to_h { |kind| [ kind, AlertChannel.for(kind) ] }
    @alerts = Readout::Alerts.new.alerts
  end
end
