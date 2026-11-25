require "tmpdir"

# Builds a throwaway stacks checkout with monitors.yml files in it (ADR 0016).
module MonitorFiles
  # Where a push comes from unless a test says otherwise: without from:, a
  # push monitor takes pushes only from the tailnet (ADR 0027).
  TAILNET_ADDRESS = "100.101.102.103"

  # files: { "monitors.yml" => { "splat" => { "http" => "..." } } }, or a raw
  # string for a file that shouldn't parse.
  def monitor_source(files = {}, name = "koti")
    @monitor_dirs ||= []
    dir = Dir.mktmpdir("pedant-source")
    @monitor_dirs << dir
    write_monitor_files(dir, files)
    Source.create!(name: name, path: dir)
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

  # Makes dir a git checkout with everything in it committed, and returns the
  # commit. Its own identity and no signing, whatever the machine's git config.
  def git_commit_all(dir)
    git = [ "git", "-C", dir, "-c", "user.name=Pedant", "-c", "user.email=pedant@example.test", "-c", "commit.gpgsign=false" ]
    system(*git, "init", "-q", exception: true)
    system(*git, "add", "-A", exception: true)
    system(*git, "commit", "-q", "--no-verify", "-m", "Monitors", exception: true)
    IO.popen([ "git", "-C", dir, "rev-parse", "HEAD" ], &:read).strip
  end

  # A source whose checkout is a git repo of these files, committed and
  # synced, so it has a commit to be read at. files: { "path" => "content" }.
  def git_source(files, name = "booko-services")
    @monitor_dirs ||= []
    dir = Dir.mktmpdir("pedant-source")
    @monitor_dirs << dir
    files.each do |relative, content|
      FileUtils.mkdir_p(File.dirname(File.join(dir, relative)))
      File.write(File.join(dir, relative), content)
    end
    git_commit_all(dir)
    Source.create!(name: name, path: dir).tap(&:sync!)
  end

  # A repo for a source to fetch from, as the forge holds it: a bare repo with
  # these monitor files committed on a branch (#12). Returns its file:// URL,
  # and a working copy that commit_upstream adds commits from.
  def upstream_repo(files, branch = "main")
    @monitor_dirs ||= []
    bare, work = Dir.mktmpdir("pedant-upstream"), Dir.mktmpdir("pedant-upstream-work")
    @monitor_dirs.push(bare, work)
    system("git", "init", "-q", "--bare", bare, exception: true)
    write_monitor_files(work, files)
    git_commit_all(work)
    system("git", "-C", work, "remote", "add", "origin", bare, exception: true)
    system("git", "-C", work, "push", "-q", "origin", "HEAD:refs/heads/#{branch}", exception: true)
    [ "file://#{bare}", work ]
  end

  # Commits these monitor files in the upstream's working copy and pushes them
  # to the branch. Returns the commit.
  def commit_upstream(work, files, branch = "main")
    write_monitor_files(work, files)
    sha = git_commit_all(work)
    system("git", "-C", work, "push", "-q", "--force", "origin", "HEAD:refs/heads/#{branch}", exception: true)
    sha
  end

  # A compose file running these images: { service => image }.
  def compose_file(services)
    { "services" => services.to_h { |service, image| [ service.to_s, { "image" => image } ] } }.to_yaml
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

# A source with a git URL fetches into Pedant's own clone (#12). Each test
# gets an empty place for clones, and ssh-keyscan never runs: every host's key
# is HOST_KEY.
module SourceClones
  HOST_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDryXvCkAqDQ295IFwNh63TwsA29uJlWi3gGoRZlnZEs".freeze
  HOST_KEY_FINGERPRINT = "SHA256:09mp5pAKWR9JbyKo9vSi/4e/c9EhKYrLQ+4dpoUeC/0".freeze

  def self.included(base)
    base.setup do
      @source_clones = Dir.mktmpdir("pedant-clones")
      Rails.configuration.x.source_clones = @source_clones
      Source::Remote.scanner = ->(host, port) { "#{port == 22 ? host : "[#{host}]:#{port}"} #{HOST_KEY}\n" }
    end
    base.teardown { FileUtils.rm_rf(@source_clones) }
  end

  # Runs the block with test/support/bin/ssh standing in for ssh, so an ssh
  # fetch runs on this machine, or fails as ssh would, saying fail. Returns
  # what the fake recorded of its last call, or nil if it wasn't called.
  def with_fake_ssh(fail: nil, hang: false, &block)
    dir = Dir.mktmpdir("pedant-fake-ssh")
    log = File.join(dir, "ssh.json")
    fake = { "PATH" => "#{Rails.root.join("test/support/bin")}:#{ENV["PATH"]}", "PEDANT_FAKE_SSH_LOG" => log,
      "SSH_AUTH_SOCK" => "/tmp/agent.sock", "PEDANT_FAKE_SSH_FAIL" => fail, "PEDANT_FAKE_SSH_HANG" => (hang ? "1" : nil) }
    saved = fake.keys.to_h { |key| [ key, ENV[key] ] }
    fake.each { |key, value| ENV[key] = value }
    block.call
    JSON.parse(File.read(log)) if File.exist?(log)
  ensure
    saved&.each { |key, value| ENV[key] = value }
    FileUtils.rm_rf(dir) if dir
  end
end

ActiveSupport::TestCase.include MonitorFiles, OfflineSwitch, SourceClones
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
