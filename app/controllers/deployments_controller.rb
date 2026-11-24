# What runs where (dkam/pedant#16). For now only git's side: each host's stacks
# from its .doco-cd.<host>.yml in every source (Readout::Deployments).
class DeploymentsController < ApplicationController
  def index
    @readout = Readout::Deployments.new
  end
end
