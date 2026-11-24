# The deployments page (dkam/pedant#16): what git says each host should run,
# from Deployments::Desired. The running side joins it once the hosts report
# (step 3), and a deployments tool over MCP reads the same thing (step 4).
class Readout::Deployments
  delegate :hosts, :reads, :problems, to: :@desired

  def initialize(desired: Deployments::Desired.new)
    @desired = desired
  end
end
