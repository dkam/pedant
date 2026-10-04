# The front page: every active monitor, down first.
class DashboardController < ApplicationController
  def show
    @monitors = Uptime::Monitor.active.by_urgency.includes(:source)
    @sources = Uptime::Source.all
  end
end
