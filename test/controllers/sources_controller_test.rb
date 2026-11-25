require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
    @dir = Dir.mktmpdir("pedant-source")
    write_monitor_files(@dir, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } })
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "adding a source needs a login" do
    post sources_url, params: { source: { name: "koti", path: @dir } }

    assert_redirected_to login_url
    assert_empty Source.all
  end

  test "adding a source syncs it straight away" do
    sign_in_with_password

    post sources_url, params: { source: { name: "koti", path: @dir } }

    assert_redirected_to settings_url
    assert_equal [ "splat" ], Source.sole.monitors.pluck(:key)
  end

  test "a path that isn't a directory is refused" do
    sign_in_with_password

    post sources_url, params: { source: { name: "koti", path: "/does/not/exist" } }

    assert_response :unprocessable_content
    assert_empty Source.all
  end

  test "changing a source's path and syncing it now" do
    sign_in_with_password
    source = Source.create!(name: "koti", path: Dir.tmpdir)

    patch source_url(source), params: { source: { path: @dir } }
    assert_redirected_to settings_url
    assert_equal [ "splat" ], source.monitors.pluck(:key)

    write_monitor_files(@dir, "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" }, "kith" => { "http" => "http://splat.local:3040/up" } })
    post sync_source_url(source)
    assert_redirected_to settings_url
    assert_equal %w[ kith splat ], source.monitors.order(:key).pluck(:key)
  end

  test "an invalid new path for a source is refused, and says why" do
    sign_in_with_password
    source = Source.create!(name: "koti", path: @dir)

    patch source_url(source), params: { source: { path: "/does/not/exist" } }

    assert_response :unprocessable_content
    assert_select "[data-source] .alert", /isn't a directory/
    assert_equal @dir, source.reload.path
  end

  test "settings list the sources and how their last sync went" do
    sign_in_with_password
    Source.create!(name: "koti", path: @dir).sync!

    get settings_url

    assert_select "[data-source]", /koti/
    assert_select "[data-source]", /1 monitor\b/
    assert_select "form[action=?]", sources_path
  end

  # The forms take their field names from the model's class, so renaming it
  # renames the parameters the controller expects.
  test "the source forms send the fields the controller expects" do
    sign_in_with_password
    source = Source.create!(name: "koti", path: @dir)

    get settings_url

    assert_select "form[action=?] input[name=?]", sources_path, "source[name]"
    assert_select "form[action=?] input[name=?]", sources_path, "source[path]"
    # A saved source's name can't be changed; only its path.
    assert_select "form[action=?] input[name=?]", source_path(source), "source[path]"
  end

  test "settings show the commit each source was synced at, and local changes" do
    sign_in_with_password
    sha = git_commit_all(@dir)
    File.write(File.join(@dir, "notes.txt"), "an edit on the host")
    Source.create!(name: "koti", path: @dir).sync!

    get settings_url

    assert_select "[data-source] code", sha[0, 7]
    assert_select "[data-source]", /local changes/
  end

  test "adding a git source fetches it straight away" do
    sign_in_with_password
    url, = upstream_repo("monitors.yml" => { "kith" => { "http" => "http://kith.local:3040/up" } })

    post sources_url, params: { source: { name: "booko-services", url: url, branch: "main", path: "" } }

    assert_redirected_to settings_url
    source = Source.sole
    assert_equal [ url, "main", nil ], [ source.url, source.branch, source.path ]
    assert_equal [ "kith" ], source.monitors.pluck(:key)
  end

  test "a local checkout added from the form keeps no branch" do
    sign_in_with_password

    post sources_url, params: { source: { name: "koti", url: "", branch: "main", path: @dir } }

    assert_equal [ @dir, nil, nil ], Source.sole.values_at(:path, :url, :branch)
  end

  test "a URL with a token in it is refused" do
    sign_in_with_password

    post sources_url, params: { source: { name: "booko-services", url: "https://dan:a-token@git.booko.info/Booko/booko-services.git", branch: "main" } }

    assert_response :unprocessable_content
    assert_empty Source.all
    assert_select ".alert", text: /credential/
  end

  test "an ssh source shows its deploy key to add to the repo, and its host keys to check" do
    sign_in_with_password
    with_fake_ssh { post sources_url, params: { source: { name: "booko-services", url: "ssh://git@forge.test/nowhere.git", branch: "main" } } }
    source = Source.sole

    get settings_url

    assert_select "[data-deploy-key] textarea", text: source.deploy_public_key
    assert_select "[data-deploy-key] textarea[name]", count: 0
    assert_select "[data-host-keys] li", text: "#{HOST_KEY_FINGERPRINT} (ED25519)"
    assert_select "[data-source] .alert", text: /Couldn't fetch main from ssh:\/\/git@forge.test\/nowhere.git/
    assert_no_match "PRIVATE KEY", response.body
  end

  test "changing a git source's branch fetches that branch" do
    sign_in_with_password
    url, work = upstream_repo("monitors.yml" => { "kith" => { "http" => "http://kith.local:3040/up" } })
    commit_upstream(work, { "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" } } }, "trial")
    source = Source.create!(name: "booko-services", url: url, branch: "main")

    patch source_url(source), params: { source: { url: url, branch: "trial" } }

    assert_redirected_to settings_url
    assert_equal [ "splat" ], source.reload.monitors.active.pluck(:key)
  end

  # grab01's booko-services began as a path. A second source for the same repo
  # would refuse every push token the first holds, and start every monitor's
  # history again.
  test "a local checkout switches to a git URL in place, and its monitors keep their history" do
    sign_in_with_password
    _token, digest = push_token
    files = { "monitors.yml" => { "splat" => { "http" => "http://splat.local:3030/up" }, "backup" => { "push" => digest, "interval" => "1d" } } }
    write_monitor_files(@dir, files)
    source = Source.create!(name: "booko-services", path: @dir).tap(&:sync!)
    monitor_ids = source.monitors.order(:key).ids
    url, = upstream_repo(files)

    get settings_url
    assert_select "[data-source] form[action='#{source_path(source)}'] input[name='source[url]']"

    patch source_url(source), params: { source: { path: "", url: url, branch: "main" } }

    assert_redirected_to settings_url
    source.reload
    assert_equal [ nil, url ], [ source.path, source.url ]
    assert_nil source.sync_errors
    assert_equal monitor_ids, source.monitors.active.order(:key).ids
  end
end
