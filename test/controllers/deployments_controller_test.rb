require "test_helper"

class DeploymentsControllerTest < ActionDispatch::IntegrationTest
  REDIS = "redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2"

  setup { create_password_owner }

  test "the deployments page needs a login" do
    get deployments_url

    assert_redirected_to login_url
  end

  test "each host lists the stacks git declares for it, with their images and the commit each source was read at" do
    sign_in_with_password
    source = git_source(
      ".doco-cd.misc01.yml" => "name: redis-booko\nworking_dir: misc01/redis-booko\n---\nname: app\nworking_dir: app\n",
      "misc01/redis-booko/compose.yaml" => compose_file(redis: REDIS),
      "app/compose.yaml" => compose_file(web: "ghcr.io/dkam/app:${TAG}")
    )
    File.write(File.join(source.path, "notes.txt"), "an edit on the host")
    source.sync!

    get deployments_url

    assert_response :success
    assert_select "header a[href=?]", deployments_path
    assert_select "[data-source-name=booko-services] code", source.commit_sha.first(7)
    assert_select "[data-source-name=booko-services]", /local changes, which aren't read/
    assert_select "[data-host=misc01] [data-stack=redis-booko]", /misc01\/redis-booko/
    assert_select "[data-host=misc01] [data-stack=redis-booko] [data-service=redis] code[title=?]", REDIS, text: "redis:7.4.10-alpine@sha256:e7723ff73d96…"
    assert_select "[data-host=misc01] [data-stack=app] [data-service=web]", /ghcr.io\/dkam\/app:\$\{TAG\}\s+as written/
  end

  test "problems in the deploy files are shown, and the rest still is" do
    sign_in_with_password
    git_source(
      ".doco-cd.misc01.yml" => "working_dir: forgot-the-name\n---\nname: redis-booko\nworking_dir: redis\n",
      "redis/compose.yaml" => compose_file(redis: REDIS)
    )

    get deployments_url

    assert_select ".alert li", "booko-services: .doco-cd.misc01.yml: stack 1 has no name"
    assert_select "[data-stack=redis-booko]"
  end

  test "with no deploy files, the page says where they come from" do
    sign_in_with_password
    monitor_source({}, "koti-stacks").sync!

    get deployments_url

    assert_select "[data-source-name=koti-stacks]", /Not a git checkout/
    assert_select "main", /No source declares a deployment yet/
  end
end
