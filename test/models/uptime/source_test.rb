require "test_helper"

class Uptime::SourceTest < ActiveSupport::TestCase
  test "monitors are read from the root file and from each stack's file, with defaults filled in" do
    source = monitor_source(
      "monitors.yml" => { "caddy" => { "http" => "https://clinch.aapamilne.com/" } },
      "splat/monitors.yml" => { "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up", "interval" => 30, "timeout" => 5, "retries" => 3 } }
    )

    source.sync!

    caddy = source.monitors.find_by!(key: "caddy")
    assert_equal [ "Caddy", "http", "https://clinch.aapamilne.com/", 60, 10, 1, "monitors.yml" ],
      [ caddy.name, caddy.kind, caddy.target, caddy.interval, caddy.timeout, caddy.retries, caddy.defined_in ]
    assert_equal({ "expect_status" => "200-299", "tls_verify" => true, "remind_every" => 86_400 }, caddy.options)

    splat = source.monitors.find_by!(key: "splat")
    assert_equal [ "Splat", 30, 5, 3, "splat/monitors.yml" ], [ splat.name, splat.interval, splat.timeout, splat.retries, splat.defined_in ]

    assert_empty source.sync_error_list
    assert source.synced_at.present?
  end

  test "a new monitor is checked straight away" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })

    freeze_time do
      source.sync!
      assert_equal Time.current, source.monitors.sole.next_check_at
    end
  end

  test "syncing again rewrites the definition and keeps what was observed" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!
    monitor = source.monitors.sole
    monitor.update!(state: "up", state_changed_at: 2.hours.ago)

    write_monitor_files(source.path, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up", "interval" => 120 } })
    source.sync!

    monitor.reload
    assert_equal 120, monitor.interval
    assert_equal "up", monitor.state
  end

  test "removing an entry retires the monitor, keeping its history, and putting it back resumes it" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" }, "kith" => { "http" => "http://splat.local:3040/up" } })
    source.sync!
    kith = source.monitors.find_by!(key: "kith")
    kith.checks.create!(status: "up", checked_at: Time.current)

    write_monitor_files(source.path, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!

    assert kith.reload.retired?
    assert_equal 1, kith.checks.count
    assert_not source.monitors.find_by!(key: "splat").retired?

    write_monitor_files(source.path, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" }, "kith" => { "http" => "http://splat.local:3040/up" } })
    source.sync!

    assert_not kith.reload.retired?
  end

  test "removing a stack's file retires its monitors" do
    source = monitor_source("splat/monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!

    remove_monitor_file(source.path, "splat/monitors.yml")
    source.sync!

    assert source.monitors.sole.retired?
  end

  test "a file that doesn't parse changes nothing, and says why" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!

    write_monitor_files(source.path, "monitors.yml" => "monitors:\n  splat: [unclosed\n")
    source.sync!

    assert_not source.monitors.sole.retired?
    assert_match %r{monitors.yml}, source.sync_error_list.join
  end

  test "an invalid entry keeps its last good definition, and the rest still apply" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!

    write_monitor_files(source.path, "monitors.yml" => {
      "splat" => { "http" => "http://splat.local:3030/up", "interval" => 5 },
      "kith" => { "http" => "http://splat.local:3040/up" }
    })
    source.sync!

    splat = source.monitors.find_by!(key: "splat")
    assert_equal 60, splat.interval
    assert_not splat.retired?
    assert source.monitors.find_by(key: "kith")
    assert_match(/splat.*interval/, source.sync_error_list.join)
  end

  test "an unknown field is an error, not a silent default" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up", "retires" => 3 } })

    source.sync!

    assert_empty source.monitors
    assert_match(/splat.*retires/, source.sync_error_list.join)
  end

  test "entries are checked" do
    source = monitor_source("monitors.yml" => {
      "no-target" => { "name" => "Nothing" },
      "ftp" => { "http" => "ftp://splat.local/" },
      "slow" => { "http" => "http://splat.local/", "interval" => 30, "timeout" => 30 },
      "Bad Key" => { "http" => "http://splat.local/" },
      "negative" => { "http" => "http://splat.local/", "retries" => -1 },
      "too-often" => { "http" => "http://splat.local/", "interval" => 10, "timeout" => 5 }
    })

    source.sync!

    assert_empty source.monitors
    errors = source.sync_error_list.join("\n")
    %w[ no-target ftp slow Bad\ Key negative too-often ].each { |key| assert_includes errors, key }
  end

  test "a key used in two files is refused in the second" do
    source = monitor_source(
      "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } },
      "splat/monitors.yml" => { "splat" => { "http" => "http://other.local/" } }
    )

    source.sync!

    assert_equal "http://splat.local:3030/up", source.monitors.sole.target
    assert_includes source.sync_error_list, "splat/monitors.yml: splat is already defined in monitors.yml"
  end

  test "a missing directory changes nothing" do
    source = monitor_source("monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
    source.sync!

    FileUtils.rm_rf(source.path)
    source.sync!

    assert_not source.monitors.sole.retired?
    assert_match(/can't read/i, source.sync_error_list.join)
  end

  test "the path must be an absolute path to a directory" do
    assert_not Uptime::Source.new(name: "koti", path: "relative/path").valid?
    assert_not Uptime::Source.new(name: "koti", path: "/does/not/exist").valid?
    assert Uptime::Source.new(name: "koti", path: Dir.tmpdir).valid?
  end

  test "a push monitor holds its token's digest, needs an interval, and gets a minute's grace" do
    _token, digest = push_token
    source = monitor_source("monitors.yml" => { "nas-backup" => { "push" => digest, "interval" => 86_400 } })

    source.sync!

    monitor = source.monitors.sole
    assert_equal [ "push", digest, 86_400, 60, 0 ], [ monitor.kind, monitor.target, monitor.interval, monitor.grace, monitor.retries ]
    assert_empty source.sync_error_list
  end

  test "a new push monitor isn't missed before it's had a chance to push" do
    _token, digest = push_token
    source = monitor_source("monitors.yml" => { "nas-backup" => { "push" => digest, "interval" => 3600, "grace" => 600 } })

    freeze_time do
      source.sync!
      assert_equal (3600 + 600).seconds.from_now, source.monitors.sole.next_check_at
    end
  end

  test "push entries are checked" do
    token, digest = push_token
    _other, other_digest = push_token("another-token")
    source = monitor_source("monitors.yml" => {
      "plain-token" => { "push" => token, "interval" => 3600 },
      "no-interval" => { "push" => other_digest },
      "http-fields" => { "push" => other_digest, "interval" => 3600, "timeout" => 5 },
      "grace-on-http" => { "http" => "http://splat.local/", "grace" => 60 },
      "first" => { "push" => digest, "interval" => 3600 },
      "same-token" => { "push" => digest, "interval" => 3600 }
    })

    source.sync!

    assert_equal [ "first" ], source.monitors.pluck(:key)
    errors = source.sync_error_list.join("\n")
    assert_match(/plain-token: .*sha256:.*pedant:push_token/, errors)
    assert_match(/no-interval: .*interval/, errors)
    assert_match(/http-fields: .*timeout/, errors)
    assert_match(/grace-on-http: .*grace/, errors)
    assert_match(/same-token: .*first/, errors)
  end

  test "a push token can't be shared with another source's monitor" do
    _token, digest = push_token
    monitor_source({ "monitors.yml" => { "backup" => { "push" => digest, "interval" => 3600 } } }, "booko").sync!
    source = monitor_source("monitors.yml" => { "nas-backup" => { "push" => digest, "interval" => 3600 } })

    source.sync!

    assert_empty source.monitors
    assert_match(/nas-backup: .*booko/, source.sync_error_list.join)
  end

  test "remind_every is a duration or never, for either kind, and defaults to a day" do
    _token, digest = push_token
    source = monitor_source("monitors.yml" => {
      "default" => { "http" => "http://splat.local/" },
      "quick" => { "http" => "http://splat.local/", "remind_every" => "6h" },
      "quiet" => { "push" => digest, "interval" => 3600, "remind_every" => "never" },
      "bad" => { "http" => "http://splat.local/", "remind_every" => "sometimes" }
    })

    source.sync!

    assert_equal({ "default" => 86_400, "quick" => 21_600, "quiet" => nil },
      source.monitors.to_h { |monitor| [ monitor.key, monitor.options["remind_every"] ] })
    assert_match(/bad: .*remind_every/, source.sync_error_list.join)
  end
end
