class MonitorsController < ApplicationController
  def show
    @monitor = Uptime::Monitor.find(params[:id])
    @checks = @monitor.checks.order(checked_at: :desc).limit(50)
    @state_changes = @monitor.state_changes.order(changed_at: :desc).limit(20)
  end
end
