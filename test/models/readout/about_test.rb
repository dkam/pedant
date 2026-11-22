require "test_helper"

class Readout::AboutTest < ActiveSupport::TestCase
  setup do
    @about = JSON.parse(Readout::About.new.to_h.to_json)
  end

  test "names its fields, and nothing else" do
    assert_equal %w[pedant ruby rails system libraries gems], @about.keys
  end

  test "says which Pedant this is, and since when it has run" do
    assert_equal Pedant::VERSION, @about.dig("pedant", "version")
    assert_equal Rails.application.config.x.revision, @about.dig("pedant", "revision")
    assert_equal "test", @about.dig("pedant", "environment")
    assert_operator Time.iso8601(@about.dig("pedant", "started_at")), :<=, Time.current
  end

  test "says which Ruby and Rails it runs on" do
    assert_equal RUBY_VERSION, @about.dig("ruby", "version")
    assert_equal RUBY_PATCHLEVEL, @about.dig("ruby", "patchlevel")
    assert_equal Rails.version, @about["rails"]
  end

  test "names the C libraries that hold most of Ruby's advisories" do
    assert_equal OpenSSL::OPENSSL_LIBRARY_VERSION, @about.dig("libraries", "openssl")
    assert_equal Psych::LIBYAML_VERSION, @about.dig("libraries", "libyaml")
    assert_match(/\A3\.\d+\.\d+\z/, @about.dig("libraries", "sqlite"))
  end

  test "names the kernel, which in a container is the host's" do
    assert_equal Etc.uname[:release], @about.dig("system", "kernel")
    assert @about["system"].key?("os")
  end

  test "lists every gem in the bundle, and the default gems the process loaded" do
    gems = @about["gems"]

    Bundler.load.specs.each { |spec| assert_equal spec.version.to_s, gems[spec.name], spec.name }
    Gem.loaded_specs.each_value { |spec| assert_equal spec.version.to_s, gems[spec.name], spec.name }
    assert_equal Rack.release, gems["rack"]
    assert_equal gems.keys.sort, gems.keys
  end

  # Default gems ship with Ruby, have advisories of their own, and are loaded
  # from Ruby's own copy unless Gemfile.lock names them, so the lockfile
  # alone would leave them out.
  test "lists Ruby's default gems the bundle doesn't name" do
    gems = @about["gems"]

    assert_equal OpenSSL::VERSION, gems["openssl"]
    assert_equal Psych::VERSION, gems["psych"]
  end

  test "carries no secret" do
    json = Readout::About.new.to_h.to_json

    assert_not_includes json, Rails.application.secret_key_base
    assert_not_includes json, Rails.root.to_s
  end
end
