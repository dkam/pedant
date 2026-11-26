# Pedant

The fleet app for Booko's hosts: what runs where, at which version, and whether
it's up. Named for its most common message: "well, actually, misc01 is running
1.12.2, and git says 1.12.3."

It replaces Uptime Kuma now, and will become a dashboard over
[doco-cd](https://github.com/kimdre/doco-cd) later. It's built for one fleet
rather than as a general product.

## What it does

- **HTTP and TCP checks** on a schedule. An HTTP check can expect a status
  range, text in the body, or values at JSON paths.
- **Push monitors** for jobs, at Kuma's URL shape
  (`/api/push/<token>?status=up&msg=…&ping=…`), so moving a job means changing
  only the hostname. A push can be on an interval or a cron schedule, mark a
  run's start, and carry a value with warn and down limits and a forecast
  ("free space reaches 0 within 3 days"). Pushes are taken only from the
  tailnet unless the monitor's `from:` names other addresses.
- **Alerts** by ntfy and email: once when a monitor goes down, on recovery,
  and as reminders while it stays down. Pedant's own outage is "unknown", which
  never alerts.
- **Monitors are defined in git.** Pedant reads `monitors.yml` files from your
  stacks repos and never edits them.
- **Desired state:** what each host should run, read from doco-cd's
  `.doco-cd.<host>.yml` files.
- **A read-only MCP server** at `POST /mcp`, so agents can ask what's up.
- **Sign-in** by a password for one owner, or OIDC.

Two rules: git holds intent and SQLite holds only what was observed, and
Pedant never offers an action that removes volumes.

## monitors.yml

Put one at the top of a stacks repo, or beside a stack's compose file.

```yaml
monitors:
  splat:
    http: https://splat.example.com/up
  kith:
    http: http://kith.local:3040/up
    interval: 60          # seconds, or 30s, 5m, 3h, 1d
    retries: 1            # failures in a row before "down"
    expect_status: 200-299
    expect_json: { queue_status: healthy }
  redis:
    tcp: redis.local:6379
  nightly-backup:
    push: sha256:9f2c…    # bin/rails pedant:push_token prints a token and this digest
    schedule: "0 2 * * *"
    timezone: Australia/Sydney
    max_runtime: 3h
  disk:
    push: sha256:41ab…
    interval: 1h
    value:
      unit: "%"
      warn_above: 80
      down_above: 90
      forecast: { reaches: 100, down_within: 3d }
```

The token goes in the job's curl and only its digest in git. Unknown keys are
errors, and a file that doesn't parse changes nothing.

## Running it

Images are at `ghcr.io/dkam/pedant:vX.Y.Z`. The app listens on port 80 and
keeps everything in `/rails/storage`.

```yaml
services:
  pedant:
    image: ghcr.io/dkam/pedant:v0.12.2
    restart: always
    environment:
      SECRET_KEY_BASE: …   # openssl rand -hex 64; changing it loses encrypted settings
      SENTRY_DSN: …        # optional, for Pedant's own errors
    ports:
      - 127.0.0.1:3036:80
    volumes:
      - ./storage:/rails/storage
```

On first start the log prints a setup code. Use it at `/setup` to claim the
instance with a password or an OIDC provider. Then add a source in Settings: a
git URL and branch. For an ssh URL, Pedant makes a deploy key to add to the
repo with read-only access.

Locked out? `bin/rails pedant:reset_password` or `pedant:reset_oidc` reopens
setup.

## Development

Ruby 4.0, Rails 8.1, SQLite, Solid Queue, Tailwind and importmaps. No Node.

```sh
bin/setup        # then starts bin/dev: http://localhost:3036, with the job runner
bin/rails test
```

## Docs and issues

Decisions are ADRs in [`docs/decisions/`](docs/decisions/), indexed in
[`docs/README.md`](docs/README.md). Issues are on Gitea (`dkam/pedant` at
git.booko.info), not GitHub.

A release is a change to `config/version.rb` on main. CI builds the image and
tags the commit.

## License

MIT. See [LICENSE](LICENSE).
