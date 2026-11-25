require "open3"
require "shellwords"

# A source's git URL, and the git and ssh that fetch it into Pedant's own clone
# (ADR 0037). Nothing here writes anywhere but that clone.
#
# - A URL is ssh, https or a local file, never carries a credential, and can't
#   be read as an option.
# - An ssh fetch offers only the source's own deploy key and accepts only the
#   host keys pinned when the source was added. Nothing of the machine's ssh or
#   git config is used, nor its agent.
class Source::Remote
  class Failed < StandardError; end

  PROTOCOLS = "ssh:https:file".freeze
  # user@host:path, as GitHub and Gitea show an ssh URL.
  SCP_LIKE = %r{\A(?<user>[A-Za-z0-9._-]+)@(?<host>[A-Za-z0-9.-]+):(?!//)(?<path>\S+)\z}
  HOST = /\A[A-Za-z0-9][A-Za-z0-9.-]*\z/
  # What the fetch writes to, so the branch never collides with anything else
  # in the clone.
  FETCHED = "refs/pedant/fetched".freeze
  TIMEOUT = 60
  SCAN_TIMEOUT = 5

  # Seconds a git command may run before it, and its ssh, are killed.
  class_attribute :timeout, default: TIMEOUT

  # How a host's keys are read: (host, port) -> known_hosts lines, or nil.
  # Tests replace it, so ssh-keyscan never reaches the network there.
  class_attribute :scanner, default: ->(host, port) do
    output, _errors, status = Open3.capture3("ssh-keyscan", "-T", SCAN_TIMEOUT.to_s, "-p", port.to_s, "--", host)
    output.lines.reject { |line| line.start_with?("#") }.join.presence if status.success?
  rescue SystemCallError
    nil
  end

  attr_reader :url

  def initialize(url)
    @url = url.to_s
  end

  # What's wrong with the URL, or nil.
  def problem
    return "can't start with -" if url.start_with?("-")
    return "can't contain spaces" if url.match?(/\s/)
    return (host.match?(HOST) ? nil : "doesn't name a host") if scp_like

    uri = URI.parse(url)
    case uri.scheme
    when "ssh"
      return "can't carry a password: Pedant fetches with its deploy key" if uri.password
    when "https"
      return "can't carry a credential: use an ssh URL and a deploy key" if uri.userinfo
    when "file"
      return uri.host.blank? && uri.path.start_with?("/") ? nil : "must be file:// and an absolute path"
    else
      return "must be ssh://, user@host:path, https:// or file://"
    end
    "doesn't name a host" unless uri.host.to_s.match?(HOST)
  rescue URI::Error
    "isn't a git URL"
  end

  def ssh? = scp_like.present? || url.start_with?("ssh://")

  def host = scp_like ? scp_like[:host] : URI.parse(url).host
  def port = (scp_like ? nil : URI.parse(url).port) || 22

  # The host as known_hosts names it.
  def host_name = port == 22 ? host : "[#{host}]:#{port}"

  def scan_host_keys = scanner.call(host, port)

  # Fetches the branch into the clone at directory and puts its files at that
  # commit, whatever was there. Returns the commit. Raises Failed, with git's
  # own words, if it can't.
  def fetch(directory, branch, deploy_key: nil, host_keys: nil)
    FileUtils.mkdir_p(directory)
    # A sync from the settings page can run beside the minute's sync.
    File.open("#{directory}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      with_env(deploy_key, host_keys) do |env|
        git(env, directory, "init", "--quiet") unless File.exist?(File.join(directory, ".git"))
        git(env, directory, "fetch", "--quiet", "--no-tags", "--no-recurse-submodules", "--", url, "+refs/heads/#{branch}:#{FETCHED}")
        commit = git(env, directory, "rev-parse", "--verify", "--quiet", "#{FETCHED}^{commit}").strip
        git(env, directory, "checkout", "--quiet", "--force", "--detach", commit)
        git(env, directory, "clean", "-ffdxq")
        commit
      end
    end
  end

  # "SHA256:09mp… (ED25519)" for a known_hosts line, as ssh-keygen -l shows
  # it. Nil if the line isn't one.
  def self.fingerprint(line)
    fields = line.split
    fields.shift if fields.first&.start_with?("@")
    _hosts, type, blob = fields
    return unless type && blob

    digest = Base64.strict_encode64(Digest::SHA256.digest(Base64.strict_decode64(blob))).delete("=")
    name = { "ssh-ed25519" => "ED25519", "ssh-rsa" => "RSA" }.fetch(type) { type.start_with?("ecdsa-") ? "ECDSA" : type }
    "SHA256:#{digest} (#{name})"
  rescue ArgumentError
    nil
  end

  # An ed25519 key pair for a source to fetch with: [private, public].
  def self.generate_key(comment)
    Dir.mktmpdir("pedant-key") do |dir|
      file = File.join(dir, "key")
      _output, errors, status = Open3.capture3("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", file)
      raise Failed, "ssh-keygen: #{errors.strip}" unless status.success?
      [ File.read(file), File.read("#{file}.pub").strip ]
    end
  end

  private
    def scp_like = @scp_like ||= SCP_LIKE.match(url)

    # The environment git runs in, and for ssh, the key and known hosts it
    # names, in files only this process can read, removed afterwards.
    def with_env(deploy_key, host_keys)
      Dir.mktmpdir("pedant-ssh") do |dir|
        env = {
          "GIT_TERMINAL_PROMPT" => "0",
          "GIT_ALLOW_PROTOCOL" => PROTOCOLS,
          "GIT_CONFIG_GLOBAL" => File::NULL,
          "GIT_CONFIG_NOSYSTEM" => "1",
          "SSH_AUTH_SOCK" => nil
        }
        env["GIT_SSH_COMMAND"] = ssh_command(dir, deploy_key, host_keys) if ssh?
        yield env
      end
    end

    def ssh_command(dir, deploy_key, host_keys)
      key = write_private(File.join(dir, "key"), deploy_key.to_s.end_with?("\n") ? deploy_key : "#{deploy_key}\n")
      known_hosts = write_private(File.join(dir, "known_hosts"), host_keys.to_s)
      [
        "ssh", "-F", File::NULL, "-i", key,
        "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=#{known_hosts}",
        "-o", "GlobalKnownHostsFile=#{File::NULL}", "-o", "UpdateHostKeys=no",
        "-o", "ConnectTimeout=10"
      ].shelljoin
    end

    def write_private(file, content)
      File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |io| io.write(content) }
      file
    end

    # Runs git in the clone, killing it and its ssh if it runs past the timeout.
    def git(env, directory, *args)
      command = [ "git", "-C", directory, "-c", "core.hooksPath=#{File::NULL}", "-c", "init.defaultBranch=pedant", *args ]
      Open3.popen3(env, *command, pgroup: true) do |stdin, stdout, stderr, wait|
        stdin.close
        readers = [ stdout, stderr ].map { |io| Thread.new { io.read } }
        finished = wait.join(timeout)
        kill_group(wait.pid) unless finished
        # Both streams are read to the end before popen3 closes them.
        output, errors = readers.map(&:value)
        raise Failed, "git #{args.first} took longer than #{timeout} #{"second".pluralize(timeout)}" unless finished
        raise Failed, summary(errors, args.first) unless wait.value.success?
        output
      end
    rescue SystemCallError => error
      raise Failed, error.message
    end

    # git and the ssh it started, so neither holds the pipes open.
    def kill_group(pid)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    end

    # git's own words, in a line: "git@git.booko.info: Permission denied
    # (publickey). fatal: Could not read from remote repository." ssh's
    # warning about a changed host key is a banner, so that one is told
    # plainly, with the key the host offered.
    def summary(errors, command)
      lines = errors.lines.map(&:strip).reject(&:empty?)
      return host_key_summary(lines) if lines.include?("Host key verification failed.")

      lines.reject { |line| line.start_with?("Please make sure", "and the repository exists") }
        .first(3).join(" ").presence || "git #{command} failed"
    end

    def host_key_summary(lines)
      offered = lines.grep(/\ASHA256:/).first&.delete_suffix(".")
      detail = if offered
        "the host offered #{offered}, which isn't one of the keys pinned for this source"
      else
        lines.grep(/host key is known for/).first&.delete_suffix(" and you have requested strict checking.")
      end
      [ "Host key verification failed", detail ].compact.join(": ")
    end
end
