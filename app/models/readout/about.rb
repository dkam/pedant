require "etc"

# What this Pedant runs, for asking whether an advisory applies to it: its
# version and revision, Ruby and Rails, the OS and the host's kernel, the C
# libraries in the process, and every gem with its version. The about tool
# over MCP; never on the public website, where it would tell anyone which
# advisories to try (ADR 0029).
#
# Like every readout, it names its fields one by one. No environment
# variable, path or setting appears.
class Readout::About
  def to_h
    {
      pedant: {
        version: Pedant::VERSION,
        revision: Rails.application.config.x.revision,
        environment: Rails.env.to_s,
        started_at: Readout.iso(Rails.application.config.x.started_at)
      },
      ruby: {
        version: RUBY_VERSION,
        patchlevel: RUBY_PATCHLEVEL,
        platform: RUBY_PLATFORM,
        yjit: defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false
      },
      rails: Rails.version,
      system: {
        # The container's own OS, from its image.
        os: os_release,
        # Containers share their host's kernel, so in one this is the host's.
        kernel: Etc.uname[:release],
        architecture: Etc.uname[:machine]
      },
      libraries: libraries,
      gems: gems
    }
  end

  private
    def os_release
      line = File.foreach("/etc/os-release").find { |line| line.start_with?("PRETTY_NAME=") }
      line&.split("=", 2)&.last&.strip&.delete('"')
    rescue Errno::ENOENT
      nil
    end

    # The versions loaded into this process, which can differ from the ones
    # Ruby was built against.
    def libraries
      xml = nokogiri_versions
      {
        openssl: OpenSSL::OPENSSL_LIBRARY_VERSION,
        sqlite: SQLite3::SQLITE_LOADED_VERSION,
        libyaml: Psych::LIBYAML_VERSION,
        zlib: Zlib.zlib_version,
        libxml2: xml&.dig("libxml", "loaded"),
        libxslt: xml&.dig("libxslt", "loaded")
      }
    end

    # Rails loads Nokogiri only when something first sanitises HTML.
    def nokogiri_versions
      require "nokogiri"
      Nokogiri::VERSION_INFO
    rescue LoadError
      nil
    end

    # Ruby's default gems (openssl, psych, …), then the bundle, then what the
    # process has loaded, each later one winning. Default gems have advisories
    # of their own, and Ruby loads its own copy unless Gemfile.lock names one,
    # so the bundle alone would leave them out.
    def gems
      specs = Gem::Specification.default_stubs + Bundler.load.specs.to_a + Gem.loaded_specs.values
      specs.to_h { |spec| [ spec.name, spec.version.to_s ] }.sort.to_h
    end
end
