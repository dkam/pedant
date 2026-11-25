require "test_helper"

class Readout::SourcesTest < ActiveSupport::TestCase
  FIELDS = %i[ id name path url branch synced_at commit_sha dirty sync_errors monitors retired_monitors ].freeze

  test "names its fields, and nothing else" do
    monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://splat.local/up" } } }).sync!

    readout = Readout::Sources.new.to_h

    assert_equal [ :sources ], readout.keys
    assert_equal FIELDS, readout[:sources].sole.keys
  end

  test "a synced git checkout: where it is, the commit it's at, and its monitors" do
    source = git_source({ "monitors.yml" => { "monitors" => {
      "splat" => { "http" => "http://splat.local/up" },
      "kith" => { "http" => "http://kith.local/up" }
    } }.to_yaml })
    sha = Source::Checkout.new(source.path).head
    File.write(File.join(source.path, "monitors.yml"), { "monitors" => { "splat" => { "http" => "http://splat.local/up" } } }.to_yaml)
    source.sync!

    readout = Readout::Sources.new.to_h[:sources].sole

    assert_equal source.id, readout[:id]
    assert_equal "booko-services", readout[:name]
    assert_equal source.path, readout[:path]
    assert_equal source.reload.synced_at.utc.iso8601, readout[:synced_at]
    assert_equal sha, readout[:commit_sha]
    assert_equal true, readout[:dirty]
    assert_equal [], readout[:sync_errors]
    assert_equal 1, readout[:monitors]
    assert_equal 1, readout[:retired_monitors]
  end

  # As on grab01 when Docker made the mount point before the clone existed.
  test "an empty directory isn't a git checkout, and has no monitors" do
    source = monitor_source
    source.sync!

    readout = Readout::Sources.new.to_h[:sources].sole

    assert_not_nil readout[:synced_at]
    assert_nil readout[:commit_sha]
    assert_nil readout[:dirty]
    assert_equal 0, readout[:monitors]
  end

  test "a source not synced yet" do
    monitor_source

    assert_nil Readout::Sources.new.to_h[:sources].sole[:synced_at]
  end

  test "why a sync went wrong, a line each" do
    monitor_source({
      "monitors.yml" => "monitors: [not, a, map",
      "kith/monitors.yml" => { "Kith" => { "http" => "http://kith.local/up" } }
    }).sync!

    errors = Readout::Sources.new.to_h[:sources].sole[:sync_errors]

    assert_equal 2, errors.size
    assert errors.any? { |error| error.start_with?("monitors.yml: ") }
    assert errors.any? { |error| error.start_with?("kith/monitors.yml: Kith: not a valid key") }
  end

  test "every source, by name, with its own monitors counted" do
    monitor_source({ "monitors.yml" => { "splat" => { "http" => "http://splat.local/up" } } }, "koti-stacks").sync!
    monitor_source({}, "booko-services").sync!

    sources = Readout::Sources.new.to_h[:sources]

    assert_equal %w[ booko-services koti-stacks ], sources.map { |source| source[:name] }
    assert_equal [ 0, 1 ], sources.map { |source| source[:monitors] }
  end
end
