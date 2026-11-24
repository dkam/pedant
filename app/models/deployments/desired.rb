# What git says each host should run: the union of every source's
# .doco-cd.<host>.yml (ADR 0030), with the images each stack's compose files
# name. Read at the commit each source last synced, never from the working
# tree, and worked out when asked rather than stored, since git holds intent
# (ADR 0032).
#
# Read as doco-cd reads it (wiki/docs/Deploy-Settings.md): one stack per YAML
# document, from the top of the repo (DEPLOY_CONFIG_BASE_DIR left at /), with
# its working_dir, compose_files, env_files, environment and profiles.
#
# A problem in a file is reported and the rest is still read, as monitors.yml
# is: one source's mistake hides none of another's stacks.
class Deployments::Desired
  DEPLOY_FILE = /\A\.doco-cd\.(?<host>[^\/]+)\.ya?ml\z/
  UNTARGETED = /\A\.doco-cd\.ya?ml\z/
  COMPOSE_FILES = %w[ compose.yaml compose.yml docker-compose.yml docker-compose.yaml ].freeze
  ENV_FILES = %w[ .env ].freeze
  ENCRYPTED = /\.sops\./

  Host = Data.define(:name, :stacks)
  # working_dir and compose_files are paths from the top of the source's repo.
  Stack = Data.define(:host, :name, :source, :file, :working_dir, :compose_files, :services, :notes)
  # image is nil for a service that's built rather than pulled. resolved is
  # false if a variable in it couldn't be filled in, so it's as written.
  Service = Data.define(:name, :image, :resolved)
  # Which commit was read from each source, or why nothing was.
  Read = Data.define(:source, :commit_sha, :note)

  def initialize(sources = Source.order(:name))
    @sources = sources
  end

  def hosts
    read
    @hosts
  end

  def reads
    read
    @reads
  end

  # What's wrong in the files: each a sentence naming the source and file.
  def problems
    read
    @problems
  end

  private
    def read
      return if @reads

      @reads, @problems, stacks, host_names = [], [], [], Set.new
      @sources.each do |source|
        read, files = read_source(source)
        @reads << read
        files&.each do |file|
          if file.match?(UNTARGETED)
            @problems << "#{source.name}: #{file} names no host, so its stacks aren't shown. Name it .doco-cd.<host>.yml"
          elsif (match = DEPLOY_FILE.match(file))
            host_names << match[:host]
            stacks.concat stacks_in(source, read.commit_sha, files, match[:host], file)
          end
        end
      end

      stacks = mark_duplicates(stacks)
      @hosts = host_names.sort.map do |host|
        Host.new(name: host, stacks: stacks.select { |stack| stack.host == host }.sort_by { |stack| [ stack.name, stack.source.name ] })
      end
    end

    # The source's commit and the files in it, or a note saying why there's
    # nothing to read. Not a problem in git: a source with only monitors needn't
    # be a git checkout.
    def read_source(source)
      commit = source.commit_sha
      return [ Read.new(source: source, commit_sha: nil, note: "Not synced yet"), nil ] unless source.synced_at
      return [ Read.new(source: source, commit_sha: nil, note: "Not a git checkout, so its deploy files aren't read"), nil ] unless commit

      files = source.checkout.files(commit)
      note = "Synced at #{commit.first(7)}, which is no longer in the checkout. The next sync reads it again" unless files
      [ Read.new(source: source, commit_sha: commit, note: note), files&.to_set ]
    end

    def stacks_in(source, commit, files, host, file)
      documents = YAML.safe_load_stream(source.checkout.read(commit, file).to_s, filename: file, aliases: true)
      documents.each_with_index.filter_map do |settings, index|
        next if settings.nil?

        problems = []
        stack = stack_for(source, commit, files, host, file, settings, index, problems)
        @problems.concat problems.map { |problem| "#{source.name}: #{file}: #{problem}" }
        stack
      end
    rescue Psych::Exception => error
      @problems << "#{source.name}: #{file}: #{error.message}"
      []
    end

    # The stack, or nil if the file doesn't say enough to show one. What would
    # stop doco-cd deploying it goes in problems; what Pedant can't see, such
    # as an encrypted value, goes in the stack's notes.
    def stack_for(source, commit, files, host, file, settings, index, problems)
      refuse = ->(problem) { problems << problem and nil }
      return refuse.("stack #{index + 1} isn't a map of settings") unless settings.is_a?(Hash)

      name = settings["name"]
      return refuse.("stack #{index + 1} has no name") unless name.is_a?(String) && name.present?

      working_dir = in_repo(settings.fetch("working_dir", ".").to_s)
      return refuse.("#{name}: working_dir #{settings["working_dir"]} is outside the repo") unless working_dir

      stack = Stack.new(host: host, name: name, source: source, file: file, working_dir: working_dir, compose_files: [], services: [], notes: [])
      if settings["repository_url"].present?
        stack.with(notes: [ "Deploys from #{settings["repository_url"]}, which Pedant doesn't read" ])
      elsif enabled?(settings["auto_discovery"])
        stack.with(notes: [ "Auto-discovery finds its stacks under #{working_dir}/, which Pedant doesn't read yet" ])
      else
        stack_problems = []
        stack = with_services(stack, settings, commit, files, stack_problems)
        problems.concat stack_problems.map { |problem| "#{name}: #{problem}" }
        stack
      end
    end

    def with_services(stack, settings, commit, files, problems)
      notes = []
      compose_files = Array(settings["compose_files"] || COMPOSE_FILES).filter_map { |compose| in_repo(stack.working_dir, compose.to_s) }.select { |path| files.include?(path) }
      problems << "no compose file in #{stack.working_dir}/" if compose_files.empty?

      services = services_in(stack.source.checkout, commit, compose_files, notes, problems)
      profiles = Array(settings["profiles"]).map(&:to_s)
      services = services.reject { |_name, service| (wanted = Array(service["profiles"]).map(&:to_s)).any? && (wanted & profiles).none? }

      variables = variables_for(stack, settings, commit, files, notes, problems) if services.any? { |_name, service| service["image"].to_s.include?("$") }
      services = services.sort.map do |name, service|
        image, resolved = service["image"]&.to_s, true
        image, resolved = variables.fill(image) if image && variables
        Service.new(name: name, image: image, resolved: resolved)
      end

      stack.with(compose_files: compose_files, services: services, notes: notes)
    end

    # Each service's settings, later compose files overriding earlier ones.
    def services_in(checkout, commit, compose_files, notes, problems)
      compose_files.each_with_object({}) do |path, services|
        compose = YAML.safe_load(checkout.read(commit, path).to_s, aliases: true, filename: path)
        next problems << "#{path} isn't a compose file" unless compose.is_a?(Hash)

        notes << "#{path} includes other files, which Pedant doesn't read" if compose.key?("include")
        (compose["services"].is_a?(Hash) ? compose["services"] : {}).each do |name, service|
          next unless service.is_a?(Hash)

          notes << "#{name} extends another service, which Pedant doesn't follow" if service.key?("extends")
          services[name.to_s] = services.fetch(name.to_s, {}).merge(service.slice("image", "build", "profiles"))
        end
      rescue Psych::Exception => error
        problems << error.message
      end
    end

    # Only read when an image has a variable in it.
    def variables_for(stack, settings, commit, files, notes, problems)
      variables = Deployments::Variables.new
      explicit = settings.key?("env_files")
      Array(settings["env_files"] || ENV_FILES).each do |entry|
        path = in_repo(stack.working_dir, entry.to_s)
        if path.nil? || !files.include?(path)
          # doco-cd ignores a missing .env, but not a file the deploy names.
          problems << "env file #{entry} isn't in the repo" if explicit
        elsif path.match?(ENCRYPTED)
          variables.add_encrypted(stack.source.checkout.read(commit, path).to_s)
          notes << "#{path} is encrypted, so an image variable it sets is shown as written"
        else
          variables.add_plaintext(stack.source.checkout.read(commit, path).to_s)
        end
      end
      (settings["environment"].is_a?(Hash) ? settings["environment"] : {}).each { |name, value| variables.set(name, value) }
      variables
    end

    def mark_duplicates(stacks)
      repeated = stacks.group_by { |stack| [ stack.host, stack.name ] }.select { |_key, group| group.many? }
      repeated.each do |(host, name), group|
        @problems << "#{host}: #{name} is declared more than once: #{group.map { |stack| "#{stack.source.name} #{stack.file}" }.join(", ")}"
      end
      stacks.map { |stack| repeated.key?([ stack.host, stack.name ]) ? stack.with(notes: stack.notes + [ "Declared more than once for #{stack.host}" ]) : stack }
    end

    # The path from the top of the repo, or nil if it leaves the repo.
    def in_repo(*parts)
      path = Pathname.new(File.join(*parts)).cleanpath.to_s
      path unless path.start_with?("/") || path == ".." || path.start_with?("../")
    end

    def enabled?(setting) = setting == true || (setting.is_a?(Hash) && setting["enabled"] == true)
end
