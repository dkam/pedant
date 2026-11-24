require "test_helper"

class Deployments::DesiredTest < ActiveSupport::TestCase
  REDIS = "redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2"
  WHOAMI = "traefik/whoami:v1.12.0@sha256:c4717a8d1f0134a7444e24f881160e033991f23027c6c5a9a3f8fd22e70d1d44"

  # misc01 in booko-services, as it is on main: two stacks, and a folder
  # doco-cd doesn't deploy yet.
  def misc01_files
    {
      ".doco-cd.misc01.yml" => <<~YAML,
        # yaml-language-server: $schema=https://doco.cd/latest/schemas/deploy.schema.json
        name: doco-trial
        working_dir: misc01/doco-trial

        ---
        # Booko's Redis.
        name: redis-booko
        working_dir: misc01/redis-booko
      YAML
      "misc01/doco-trial/compose.yaml" => compose_file(whoami: WHOAMI),
      "misc01/redis-booko/compose.yaml" => compose_file(redis: REDIS),
      "misc01/kuma/docker-compose.yaml" => compose_file(kuma: "louislam/uptime-kuma:1")
    }
  end

  def images(stack) = stack.services.to_h { |service| [ service.name, service.image ] }

  def stack(desired, name) = desired.hosts.flat_map(&:stacks).find { |stack| stack.name == name }

  test "a host's stacks come from its .doco-cd.<host>.yml, with the images their compose files name" do
    git_source(misc01_files)

    desired = Deployments::Desired.new

    host = desired.hosts.sole
    assert_equal "misc01", host.name
    assert_equal %w[ doco-trial redis-booko ], host.stacks.map(&:name)
    redis = host.stacks.last
    assert_equal({ "redis" => REDIS }, images(redis))
    assert_equal "booko-services", redis.source.name
    assert_equal ".doco-cd.misc01.yml", redis.file
    assert_equal "misc01/redis-booko", redis.working_dir
    assert_equal [ "misc01/redis-booko/compose.yaml" ], redis.compose_files
    assert_empty desired.problems
  end

  test "stacks are read at the commit the source last synced, not from the working tree" do
    source = git_source(misc01_files)
    compose = File.join(source.path, "misc01/redis-booko/compose.yaml")
    File.write(compose, compose_file(redis: "redis:8"))

    assert_equal({ "redis" => REDIS }, images(stack(Deployments::Desired.new, "redis-booko")), "an edit on the host isn't intent")

    git_commit_all(source.path)
    assert_equal({ "redis" => REDIS }, images(stack(Deployments::Desired.new, "redis-booko")), "not until the next sync reads the commit")

    source.sync!
    assert_equal({ "redis" => "redis:8" }, images(stack(Deployments::Desired.new, "redis-booko")))
  end

  test "a host's stacks from every source are shown together, each with its source" do
    git_source(misc01_files)
    git_source({
      ".doco-cd.misc01.yml" => "name: relay\nworking_dir: relay\n",
      "relay/compose.yml" => compose_file(relay: "n0computer/iroh-relay:v0.35.0")
    }, "silodrive-infra")

    host = Deployments::Desired.new.hosts.sole

    assert_equal %w[ doco-trial redis-booko relay ], host.stacks.map(&:name)
    assert_equal "silodrive-infra", host.stacks.last.source.name
  end

  test "each .doco-cd.<host>.yml is its own host" do
    git_source(misc01_files.merge(
      ".doco-cd.hetz01.yaml" => "name: caddy\nworking_dir: hetz01/caddy\n",
      "hetz01/caddy/compose.yaml" => compose_file(caddy: "caddy:2.10")
    ))

    assert_equal %w[ hetz01 misc01 ], Deployments::Desired.new.hosts.map(&:name)
  end

  test "the same stack declared twice for a host is a problem, and both are shown" do
    git_source(misc01_files)
    git_source({ ".doco-cd.misc01.yml" => "name: redis-booko\nworking_dir: redis\n", "redis/compose.yaml" => compose_file(redis: "redis:8") }, "koti-stacks")

    desired = Deployments::Desired.new

    assert_equal 2, desired.hosts.sole.stacks.count { |stack| stack.name == "redis-booko" }
    assert_includes desired.problems, "misc01: redis-booko is declared more than once: booko-services .doco-cd.misc01.yml, koti-stacks .doco-cd.misc01.yml"
  end

  test "compose_files are read in order, a later one overriding an earlier one, and missing ones are skipped" do
    git_source(
      ".doco-cd.misc01.yml" => <<~YAML,
        name: app
        compose_files: [ compose.yaml, compose.prod.yaml, compose.missing.yaml ]
      YAML
      "compose.yaml" => compose_file(web: "app:1", worker: "app:1"),
      "compose.prod.yaml" => compose_file(web: "app:2")
    )

    app = stack(Deployments::Desired.new, "app")

    assert_equal ".", app.working_dir
    assert_equal %w[ compose.yaml compose.prod.yaml ], app.compose_files
    assert_equal({ "web" => "app:2", "worker" => "app:1" }, images(app))
  end

  test "compose anchors and merge keys are followed" do
    git_source(
      ".doco-cd.misc01.yml" => "name: app\nworking_dir: app\n",
      "app/compose.yaml" => <<~YAML
        x-app: &app
          image: ghcr.io/dkam/app:1.4.0
          restart: unless-stopped
        services:
          web:
            <<: *app
          jobs:
            <<: *app
            command: bin/jobs
      YAML
    )

    assert_equal({ "jobs" => "ghcr.io/dkam/app:1.4.0", "web" => "ghcr.io/dkam/app:1.4.0" }, images(stack(Deployments::Desired.new, "app")))
  end

  test "a variable in an image is filled in from the stack's plaintext .env and the deploy file's environment" do
    git_source(
      ".doco-cd.misc01.yml" => <<~YAML,
        name: app
        working_dir: app
        environment:
          REGISTRY: ghcr.io/dkam
      YAML
      "app/.env" => "# The release\nexport TAG=1.4.0\nREGISTRY=docker.io/dkam\nQUOTED=\"v-${TAG}\" # a comment\n",
      "app/compose.yaml" => compose_file(
        web: "${REGISTRY}/app:${TAG}",
        jobs: "$REGISTRY/app:${QUOTED}",
        sidecar: "${SIDECAR_IMAGE:-busybox:1.37}",
        literal: "app:$${TAG}"
      )
    )

    app = stack(Deployments::Desired.new, "app")

    assert_equal({ "jobs" => "ghcr.io/dkam/app:v-1.4.0", "literal" => "app:${TAG}", "sidecar" => "busybox:1.37", "web" => "ghcr.io/dkam/app:1.4.0" }, images(app))
    assert app.services.all?(&:resolved)
  end

  # A SOPS dotenv file encrypts values, not keys, so Pedant can tell which
  # variables it sets without decrypting it.
  test "a variable a SOPS file sets stays as written, since Pedant never decrypts" do
    git_source(
      ".doco-cd.misc01.yml" => <<~YAML,
        name: app
        working_dir: app
        env_files: [ .env, secrets/app.sops.env ]
      YAML
      "app/.env" => "TAG=1.4.0\nSHARED=plain\n",
      "app/secrets/app.sops.env" => "PRIVATE_TAG=ENC[AES256_GCM,data:abc,type:str]\nSHARED=ENC[AES256_GCM,data:def,type:str]\nsops_version=3.9.4\n",
      "app/compose.yaml" => compose_file(web: "app:${TAG}", worker: "app:${PRIVATE_TAG}", jobs: "app:${SHARED}", sidecar: "${SIDECAR:-busybox:1.37}")
    )

    app = stack(Deployments::Desired.new, "app")

    assert_equal({ "jobs" => "app:${SHARED}", "sidecar" => "busybox:1.37", "web" => "app:1.4.0", "worker" => "app:${PRIVATE_TAG}" }, images(app))
    assert_equal({ "jobs" => false, "sidecar" => true, "web" => true, "worker" => false }, app.services.to_h { |service| [ service.name, service.resolved ] })
    assert_includes app.notes, "app/secrets/app.sops.env is encrypted, so an image variable it sets is shown as written"
  end

  test "an encrypted file Pedant can't see the keys of leaves every variable it could set as written" do
    git_source(
      ".doco-cd.misc01.yml" => "name: app\nenv_files: [ .env, secrets.sops.env, late.env ]\n",
      ".env" => "TAG=1.4.0\n",
      "secrets.sops.env" => "{\"data\": \"ENC[AES256_GCM,data:abc]\", \"sops\": {}}\n",
      "late.env" => "LATE=2\n",
      "compose.yaml" => compose_file(web: "app:${TAG}", worker: "app:${LATE}")
    )

    assert_equal({ "web" => "app:${TAG}", "worker" => "app:2" }, images(stack(Deployments::Desired.new, "app")))
  end

  test "a variable nothing sets stays as written" do
    git_source(".doco-cd.misc01.yml" => "name: app\n", "compose.yaml" => compose_file(web: "app:${TAG}"))

    web = stack(Deployments::Desired.new, "app").services.sole

    assert_equal "app:${TAG}", web.image
    assert_not web.resolved
  end

  test "a service in a profile the deploy doesn't use isn't deployed" do
    compose = { "services" => { "web" => { "image" => "app:1" }, "debug" => { "image" => "busybox:1.37", "profiles" => [ "debug" ] } } }.to_yaml
    git_source(
      ".doco-cd.misc01.yml" => "name: app\nworking_dir: app\n---\nname: app-debug\nworking_dir: app\nprofiles: [ debug ]\n",
      "app/compose.yaml" => compose
    )
    desired = Deployments::Desired.new

    assert_equal %w[ web ], stack(desired, "app").services.map(&:name)
    assert_equal %w[ debug web ], stack(desired, "app-debug").services.map(&:name)
  end

  test "a service built from a Dockerfile has no image" do
    compose = { "services" => { "web" => { "build" => "." } } }.to_yaml
    git_source(".doco-cd.misc01.yml" => "name: app\n", "compose.yaml" => compose)

    web = stack(Deployments::Desired.new, "app").services.sole

    assert_nil web.image
  end

  test "a stack from another repo, or found by auto-discovery, says so rather than guessing" do
    git_source(".doco-cd.misc01.yml" => <<~YAML)
      name: elsewhere
      repository_url: https://git.booko.info/Booko/other.git
      reference: main
      ---
      name: apps
      working_dir: apps
      auto_discovery:
        enabled: true
    YAML
    desired = Deployments::Desired.new

    assert_empty stack(desired, "elsewhere").services
    assert_includes stack(desired, "elsewhere").notes, "Deploys from https://git.booko.info/Booko/other.git, which Pedant doesn't read"
    assert_empty stack(desired, "apps").services
    assert_includes stack(desired, "apps").notes, "Auto-discovery finds its stacks under apps/, which Pedant doesn't read yet"
  end

  test "a stack doco-cd couldn't deploy is a problem: no compose file, a compose file that doesn't parse, or a missing env file" do
    git_source(
      ".doco-cd.misc01.yml" => "name: empty\nworking_dir: empty\n---\nname: broken\nworking_dir: broken\n---\nname: app\nworking_dir: app\nenv_files: [ app.env ]\n",
      "empty/README.md" => "Nothing here yet\n",
      "broken/compose.yaml" => "services: [ unclosed\n",
      "app/compose.yaml" => compose_file(web: "app:${TAG}")
    )

    desired = Deployments::Desired.new

    assert_equal %w[ app broken empty ], desired.hosts.sole.stacks.map(&:name)
    assert_includes desired.problems, "booko-services: .doco-cd.misc01.yml: empty: no compose file in empty/"
    assert desired.problems.any? { |problem| problem.start_with?("booko-services: .doco-cd.misc01.yml: broken: (broken/compose.yaml): ") }
    assert_includes desired.problems, "booko-services: .doco-cd.misc01.yml: app: env file app.env isn't in the repo"
  end

  test "a deploy file that doesn't parse, a stack without a name, or a working_dir outside the repo is a problem, and the rest is still read" do
    git_source(misc01_files)
    git_source({
      ".doco-cd.misc01.yml" => "name: [ unclosed\n",
      ".doco-cd.hetz01.yml" => "name: caddy\n---\nworking_dir: forgot-the-name\n---\nname: sneaky\nworking_dir: ../../etc\n---\n- a list\n",
      "compose.yaml" => compose_file(caddy: "caddy:2.10")
    }, "koti-stacks")

    desired = Deployments::Desired.new

    assert_equal %w[ doco-trial redis-booko ], desired.hosts.find { |host| host.name == "misc01" }.stacks.map(&:name)
    assert_equal %w[ caddy ], desired.hosts.find { |host| host.name == "hetz01" }.stacks.map(&:name)
    assert_equal 4, desired.problems.size
    assert desired.problems.any? { |problem| problem.start_with?("koti-stacks: .doco-cd.misc01.yml: ") }
    assert_includes desired.problems, "koti-stacks: .doco-cd.hetz01.yml: stack 2 has no name"
    assert_includes desired.problems, "koti-stacks: .doco-cd.hetz01.yml: sneaky: working_dir ../../etc is outside the repo"
    assert_includes desired.problems, "koti-stacks: .doco-cd.hetz01.yml: stack 4 isn't a map of settings"
  end

  test "a .doco-cd.yml without a host is a problem, since Pedant can't tell which host reads it" do
    git_source(".doco-cd.yml" => "name: app\n", "compose.yaml" => compose_file(web: "app:1"))

    desired = Deployments::Desired.new

    assert_empty desired.hosts
    assert_equal [ "booko-services: .doco-cd.yml names no host, so its stacks aren't shown. Name it .doco-cd.<host>.yml" ], desired.problems
  end

  # Not a problem in git, so they're said beside the source, not as an alert:
  # a source that only has monitors needn't be a git checkout.
  test "a source that isn't a git checkout, or hasn't synced, gives no stacks and says why" do
    git_source(misc01_files)
    monitor_source({}, "koti-stacks").sync!
    Source.create!(name: "fresh", path: Dir.tmpdir)

    desired = Deployments::Desired.new

    assert_equal %w[ misc01 ], desired.hosts.map(&:name)
    assert_empty desired.problems
    notes = desired.reads.to_h { |read| [ read.source.name, read.note ] }
    assert_nil notes["booko-services"]
    assert_equal "Not a git checkout, so its deploy files aren't read", notes["koti-stacks"]
    assert_equal "Not synced yet", notes["fresh"]
  end

  test "a commit that's gone from the checkout gives no stacks until the next sync" do
    source = git_source(misc01_files)
    source.update!(commit_sha: "0" * 40)

    desired = Deployments::Desired.new

    assert_empty desired.hosts
    assert_equal "Synced at 0000000, which is no longer in the checkout. The next sync reads it again", desired.reads.sole.note
  end
end
