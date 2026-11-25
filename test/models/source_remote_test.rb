require "test_helper"

# A source can be a git URL and a branch, which Pedant clones and fetches
# itself, rather than a checkout someone else keeps current (#12, ADR 0037).
class SourceRemoteTest < ActiveSupport::TestCase
  SPLAT = { "splat" => { "http" => "http://splat.local:3030/up" } }.freeze
  KITH = { "kith" => { "http" => "http://kith.local:3040/up" } }.freeze

  test "a source with a git URL is cloned into Pedant's own storage, and synced at the branch's commit" do
    url, work = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: url, branch: "main")

    source.sync!

    assert_equal [ "splat" ], source.monitors.active.pluck(:key)
    assert_equal [ head(work), false ], [ source.commit_sha, source.dirty ]
    assert_nil source.sync_errors
    assert_nil source.path
    assert source.checkout.directory.start_with?(Rails.configuration.x.source_clones.to_s)
  end

  # As in production, where nothing sets it: config.x answers a key that was
  # never set with an empty set of options, not nil.
  test "sources are cloned under storage/sources unless told otherwise" do
    Rails.configuration.x.instance_variable_get(:@configurations).delete(:source_clones)

    assert_equal Rails.root.join("storage", "sources"), Source.clones_root
  end

  test "each sync fetches, so a commit on the branch is read within the minute" do
    url, work = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: url, branch: "main")
    source.sync!

    sha = commit_upstream(work, "monitors.yml" => SPLAT.merge(KITH))
    source.sync!

    assert_equal %w[ kith splat ], source.monitors.active.order(:key).pluck(:key)
    assert_equal sha, source.commit_sha
  end

  test "the branch named is the one read" do
    url, work = upstream_repo("monitors.yml" => SPLAT)
    sha = commit_upstream(work, { "monitors.yml" => KITH }, "trial")
    source = Source.create!(name: "booko-services", url: url, branch: "trial")

    source.sync!

    assert_equal [ "kith" ], source.monitors.active.pluck(:key)
    assert_equal sha, source.commit_sha
  end

  test "a fetch that fails changes no monitor and keeps the commit, and says why" do
    url, = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: url, branch: "main")
    source.sync!
    synced = source.commit_sha

    FileUtils.rm_rf(url.delete_prefix("file://"))
    source.sync!

    assert_equal [ "splat" ], source.monitors.active.pluck(:key)
    assert_equal synced, source.commit_sha
    assert_match "Couldn't fetch main from #{url}", source.sync_errors
  end

  test "a branch that isn't there is a fetch error" do
    url, = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: url, branch: "mian")

    source.sync!

    assert_empty source.monitors
    assert_nil source.commit_sha
    assert_match "Couldn't fetch mian from #{url}", source.sync_errors
  end

  # Pedant's clone is its own, and is put back to the fetched commit each time.
  test "a file left in Pedant's clone isn't read" do
    url, = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: url, branch: "main")
    source.sync!

    write_monitor_files(source.checkout.directory, "monitors.yml" => KITH, "stray/monitors.yml" => KITH)
    source.sync!

    assert_equal [ "splat" ], source.monitors.active.pluck(:key)
    assert_equal false, source.dirty
  end

  test "a source is a path or a URL, not both or neither" do
    url, = upstream_repo("monitors.yml" => SPLAT)

    assert_not Source.new(name: "both", path: Dir.tmpdir, url: url, branch: "main").valid?
    assert_not Source.new(name: "neither").valid?
    assert_not Source.new(name: "no branch", url: url).valid?
  end

  test "a URL must be ssh, https or a file, and carry no credential" do
    valid = [
      "ssh://git@git.booko.info:2222/Booko/booko-services.git",
      "git@github.com:dkam/pedant.git",
      "https://github.com/dkam/pedant.git",
      "file:///srv/booko-services"
    ]
    invalid = [
      "https://dan:a-token@git.booko.info/Booko/booko-services.git",
      "https://a-token@git.booko.info/Booko/booko-services.git",
      "ssh://git:a-password@git.booko.info/Booko/booko-services.git",
      "ext::sh -c touch% /tmp/pwned",
      "--upload-pack=touch /tmp/pwned",
      "http://git.booko.info/Booko/booko-services.git",
      "git.booko.info/Booko/booko-services",
      "ssh://-oProxyCommand=sh/repo"
    ]

    valid.each { |url| assert Source.new(name: "repo", url: url, branch: "main").valid?, "expected #{url} to be taken" }
    invalid.each { |url| assert_not Source.new(name: "repo", url: url, branch: "main").valid?, "expected #{url} to be refused" }
  end

  test "a branch must be a branch name" do
    url, = upstream_repo("monitors.yml" => SPLAT)

    %w[ main release/1.2 doco-trial ].each { |branch| assert Source.new(name: "r", url: url, branch: branch).valid?, branch }
    [ "-f", "main..x", "a branch", "refs/heads/../x", "main:refs/heads/x" ].each do |branch|
      assert_not Source.new(name: "r", url: url, branch: branch).valid?, "expected #{branch} to be refused"
    end
  end

  # The private key never leaves Pedant: it's made here, and the owner adds the
  # public half to the repo as a read-only deploy key.
  test "an ssh source gets a deploy key of its own, kept encrypted" do
    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main")
    other = Source.create!(name: "koti-stacks", url: "git@git.booko.info:dkam/koti-stacks.git", branch: "main")

    assert_match(/\Assh-ed25519 \S+ pedant booko-services\z/, source.deploy_public_key)
    assert_match "BEGIN OPENSSH PRIVATE KEY", source.deploy_key
    assert_not_equal source.deploy_public_key, other.deploy_public_key

    stored = Source.connection.select_value("SELECT deploy_key FROM sources WHERE id = #{source.id}")
    assert_no_match "PRIVATE KEY", stored
    assert_no_match "PRIVATE KEY", source.inspect
  end

  test "saving again keeps the deploy key" do
    source = Source.create!(name: "booko-services", url: "git@git.booko.info:Booko/booko-services.git", branch: "main")

    assert_no_changes(-> { source.reload.deploy_public_key }) { source.update!(branch: "trial", url: "git@git.booko.info:Booko/services.git") }
  end

  test "an https or file source has no deploy key" do
    url, = upstream_repo("monitors.yml" => SPLAT)

    assert_nil Source.create!(name: "local", url: url, branch: "main").deploy_public_key
    assert_nil Source.create!(name: "public", url: "https://github.com/dkam/pedant.git", branch: "main").deploy_public_key
  end

  # Not trust on first use at each fetch: the keys are read once, shown to the
  # owner to check against the forge's, and only they are accepted after that.
  test "an ssh source pins its host's keys when it's added" do
    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main")

    assert_equal "[git.booko.info]:2222 #{HOST_KEY}", source.host_keys.strip
    assert_equal [ "#{HOST_KEY_FINGERPRINT} (ED25519)" ], source.host_key_fingerprints
  end

  test "the keys are read again only when the URL names another host" do
    source = Source.create!(name: "booko-services", url: "git@git.booko.info:Booko/booko-services.git", branch: "main")
    scans = 0
    Source::Remote.scanner = ->(host, _port) { scans += 1; "#{host} #{HOST_KEY}" }

    source.update!(url: "git@git.booko.info:Booko/services.git", branch: "trial")
    assert_equal 0, scans

    source.update!(url: "git@github.com:dkam/booko-services.git")
    assert_equal 1, scans
    assert_equal "github.com #{HOST_KEY}", source.host_keys.strip
  end

  test "keys the owner pastes are kept, not read again" do
    pasted = "[git.booko.info]:2222 #{HOST_KEY}"
    Source::Remote.scanner = ->(*) { flunk "keys were scanned" }

    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main", host_keys: pasted)

    assert_equal pasted, source.host_keys
  end

  test "a host whose keys can't be read can't be added" do
    Source::Remote.scanner = ->(*) { nil }

    source = Source.new(name: "booko-services", url: "git@git.booko.info:Booko/booko-services.git", branch: "main")

    assert_not source.save
    assert_match "git.booko.info", source.errors[:host_keys].to_sentence
  end

  test "pasted host keys must be known_hosts lines" do
    source = Source.new(name: "r", url: "git@git.booko.info:Booko/booko-services.git", branch: "main", host_keys: "SHA256:09mp5pAKWR9")

    assert_not source.valid?
    assert source.errors[:host_keys].any?
  end

  test "an ssh fetch uses only the source's key and its pinned host keys, and nothing of the machine's" do
    bare_url, = upstream_repo("monitors.yml" => SPLAT)
    source = Source.create!(name: "booko-services", url: "ssh://git@forge.test#{bare_url.delete_prefix("file://")}", branch: "main")

    ssh = with_fake_ssh { source.sync! }

    assert_nil source.sync_errors
    assert_equal [ "splat" ], source.monitors.active.pluck(:key)
    assert_equal "git@forge.test", ssh["host"]
    assert_equal source.deploy_key, ssh["identity"]
    assert_equal "600", ssh["identity_mode"]
    assert_equal source.host_keys, ssh["known_hosts"]
    assert_equal "/dev/null", ssh["flags"]["-F"]
    assert_includes ssh["options"], "StrictHostKeyChecking=yes"
    assert_includes ssh["options"], "IdentitiesOnly=yes"
    assert_includes ssh["options"], "GlobalKnownHostsFile=/dev/null"
    assert_includes ssh["options"], "BatchMode=yes"
    assert_nil ssh["agent"]
    assert_not File.exist?(ssh["flags"]["-i"]), "the key's copy on disk is removed after the fetch"
  end

  # OpenSSH 10.6's own words, from git.booko.info with a wrong key pinned.
  CHANGED_HOST_KEY = <<~SSH.gsub("\n", "\r\n")
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
    Someone could be eavesdropping on you right now (man-in-the-middle attack)!
    It is also possible that a host key has just been changed.
    The fingerprint for the ED25519 key sent by the remote host is
    SHA256:43p91iLUp9JAAj7kfNKETCVnOWmi/Zi6fOmBZrwWzXk.
    Please contact your system administrator.
    Add correct host key in /tmp/pedant-ssh/known_hosts to get rid of this message.
    Offending ED25519 key in /tmp/pedant-ssh/known_hosts:1
    Host key for [git.booko.info]:2222 has changed and you have requested strict checking.
    Host key verification failed.
    fatal: Could not read from remote repository.
  SSH

  test "a host that offers a key that isn't pinned is refused, saying which key it offered" do
    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main")

    with_fake_ssh(fail: CHANGED_HOST_KEY) { source.sync! }

    assert_equal "Couldn't fetch main from ssh://git@git.booko.info:2222/Booko/booko-services.git: Host key verification failed: " \
      "the host offered SHA256:43p91iLUp9JAAj7kfNKETCVnOWmi/Zi6fOmBZrwWzXk, which isn't one of the keys pinned for this source", source.sync_errors
  end

  test "a host with no key pinned for it is refused, saying so" do
    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main")
    unknown = "No ED25519 host key is known for [git.booko.info]:2222 and you have requested strict checking.\r\nHost key verification failed.\r\n"

    with_fake_ssh(fail: unknown) { source.sync! }

    assert_match "Host key verification failed: No ED25519 host key is known for [git.booko.info]:2222", source.sync_errors
  end

  # The minute's sync fetches every source in turn, so one that hangs mustn't
  # hold up the rest.
  test "a fetch that hangs is stopped, ssh with it, and counts as failed" do
    source = Source.create!(name: "booko-services", url: "ssh://git@forge.test/booko-services.git", branch: "main")
    Source::Remote.timeout = 1

    ssh = with_fake_ssh(hang: true) { source.sync! }

    assert_equal "Couldn't fetch main from ssh://git@forge.test/booko-services.git: git fetch took longer than 1 second", source.sync_errors
    assert_raises(Errno::ESRCH) { Process.kill(0, ssh["pid"]) }
  ensure
    Source::Remote.timeout = Source::Remote::TIMEOUT
  end

  test "the readout names the URL and branch, and never a key" do
    source = Source.create!(name: "booko-services", url: "ssh://git@git.booko.info:2222/Booko/booko-services.git", branch: "main")

    readout = Readout::Sources.new.to_h[:sources].sole

    assert_equal [ "ssh://git@git.booko.info:2222/Booko/booko-services.git", "main", nil ], readout.values_at(:url, :branch, :path)
    assert_no_match(/PRIVATE KEY|ssh-ed25519|#{Regexp.escape(source.deploy_public_key.split[1])}/, readout.to_json)
  end

  private
    def head(work) = IO.popen([ "git", "-C", work, "rev-parse", "HEAD" ], &:read).strip
end
