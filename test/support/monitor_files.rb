require "tmpdir"

# Builds a throwaway stacks checkout with monitors.yml files in it (ADR 0016).
module MonitorFiles
  # files: { "monitors.yml" => { "splat" => { "http" => "..." } } }, or a raw
  # string for a file that shouldn't parse.
  def monitor_source(files = {}, name = "koti")
    @monitor_dirs ||= []
    dir = Dir.mktmpdir("pedant-source")
    @monitor_dirs << dir
    write_monitor_files(dir, files)
    Uptime::Source.create!(name: name, path: dir)
  end

  def write_monitor_files(dir, files)
    files.each do |relative, content|
      path = File.join(dir, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content.is_a?(String) ? content : { "monitors" => content }.to_yaml)
    end
  end

  # A push monitor's token, and the digest monitors.yml holds for it.
  def push_token(token = "a-push-token-for-tests")
    [ token, "sha256:#{Digest::SHA256.hexdigest(token)}" ]
  end

  def remove_monitor_file(dir, relative)
    File.delete(File.join(dir, relative))
  end

  def self.included(base)
    base.teardown { Array(@monitor_dirs).each { |dir| FileUtils.rm_rf(dir) } }
  end
end

# Connectivity probes never leave the test: each test says whether Pedant is
# online.
module OfflineSwitch
  def pedant_online!
    Uptime::Connectivity.probe = ->(_host, _port) { true }
    Uptime::Connectivity.reset
  end

  def pedant_offline!
    Uptime::Connectivity.probe = ->(_host, _port) { false }
    Uptime::Connectivity.reset
  end
end

ActiveSupport::TestCase.include MonitorFiles, OfflineSwitch
ActiveSupport::TestCase.setup { pedant_online! }

# Alert channels for tests (ADR 0013). ntfy requests are stubbed by the test.
module AlertChannels
  NTFY_URL = "https://ntfy.example.test/pedant"

  def ntfy_channel!(token: "ntfy-secret-token", enabled: true)
    AlertChannel::Ntfy.create!(enabled: enabled, settings: { "url" => NTFY_URL, "link_base" => "http://pedant.test" }, secret: token)
  end

  def email_channel!(enabled: true)
    AlertChannel::Email.create!(enabled: enabled, secret: "smtp-password", settings: {
      "address" => "smtp.example.test", "port" => 587, "user_name" => "pedant", "from" => "pedant@example.test",
      "to" => "dan@example.com, ops@example.com", "link_base" => "http://pedant.test"
    })
  end
end

ActiveSupport::TestCase.include AlertChannels
