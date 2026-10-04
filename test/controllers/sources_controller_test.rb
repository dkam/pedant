require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
    @dir = Dir.mktmpdir("pedant-source")
    write_monitor_files(@dir, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "adding a source needs a login" do
    post sources_url, params: { uptime_source: { name: "koti", path: @dir } }

    assert_redirected_to login_url
    assert_empty Uptime::Source.all
  end

  test "adding a source syncs it straight away" do
    sign_in_with_password

    post sources_url, params: { uptime_source: { name: "koti", path: @dir } }

    assert_redirected_to settings_url
    assert_equal [ "splat" ], Uptime::Source.sole.monitors.pluck(:key)
  end

  test "a path that isn't a directory is refused" do
    sign_in_with_password

    post sources_url, params: { uptime_source: { name: "koti", path: "/does/not/exist" } }

    assert_response :unprocessable_content
    assert_empty Uptime::Source.all
  end

  test "changing a source's path and syncing it now" do
    sign_in_with_password
    source = Uptime::Source.create!(name: "koti", path: Dir.tmpdir)

    patch source_url(source), params: { uptime_source: { path: @dir } }
    assert_redirected_to settings_url
    assert_equal [ "splat" ], source.monitors.pluck(:key)

    write_monitor_files(@dir, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" }, "kith" => { "http" => "http://splat.local:3040/up" } })
    post sync_source_url(source)
    assert_redirected_to settings_url
    assert_equal %w[ kith splat ], source.monitors.order(:key).pluck(:key)
  end

  test "an invalid new path for a source is refused, and says why" do
    sign_in_with_password
    source = Uptime::Source.create!(name: "koti", path: @dir)

    patch source_url(source), params: { uptime_source: { path: "/does/not/exist" } }

    assert_response :unprocessable_content
    assert_select "[data-source] .alert", /isn't a directory/
    assert_equal @dir, source.reload.path
  end

  test "settings list the sources and how their last sync went" do
    sign_in_with_password
    Uptime::Source.create!(name: "koti", path: @dir).sync!

    get settings_url

    assert_select "[data-source]", /koti/
    assert_select "form[action=?]", sources_path
  end
end
