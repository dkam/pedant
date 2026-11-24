# The front page: every active monitor, down first (Readout::Monitors).
class DashboardController < ApplicationController
  def show
    @readout = Readout::Monitors.new
    @monitors = @readout.monitors
    @sources = Source.all
  end
end
