module PedantMcp
  class About < MCP::Tool
    tool_name "about"
    description "What this Pedant runs: its version and git revision, when the process started, Ruby and Rails, " \
      "the container's OS and the host's kernel, the C libraries in the process (OpenSSL, SQLite, libyaml, zlib, " \
      "libxml2, libxslt), and every gem with its version, including Ruby's default gems such as uri and json. " \
      "For checking whether an advisory applies to Pedant itself."
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(server_context: nil)
      PedantMcp.ok(Readout::About.new.to_h)
    end
  end
end
