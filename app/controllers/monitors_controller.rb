class MonitorsController < ApplicationController
  def show
    @monitor = Uptime::Monitor.find(params[:id])
    history = Readout::History.new(@monitor)
    @checks = history.checks
    @state_changes = history.state_changes
    @chart_checks = history.chart_checks
  end
end
