# Hiding a down monitor for its current outage (ADR 0033): until its next run
# (a push monitor), or for 24 hours. Showing it again undoes that.
class MonitorHidesController < ApplicationController
  before_action :set_monitor

  def create
    if @monitor.hide!(until_next_run: params[:until] == "next_run")
      redirect_to monitor_path(@monitor), notice: "#{@monitor.name} is hidden #{helpers.hidden_in_words(@monitor)}."
    else
      redirect_to monitor_path(@monitor), alert: "Only a down monitor can be hidden."
    end
  end

  def destroy
    @monitor.show_again!
    redirect_to monitor_path(@monitor), notice: "#{@monitor.name} is shown again."
  end

  private
    def set_monitor
      @monitor = Uptime::Monitor.find(params[:monitor_id])
    end
end
