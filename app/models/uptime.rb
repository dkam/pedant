# Uptime checks (milestone 1, ADR 0004). Monitors are defined in git (ADR 0016);
# this namespace holds what Pedant observes about them.
#
# Namespaced because a top-level Monitor would collide with Ruby's own.
module Uptime
  def self.table_name_prefix = "uptime_"
end
