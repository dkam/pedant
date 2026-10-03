# doco-cd

Facts about doco-cd (github.com/kimdre/doco-cd), the agent that applies compose
stacks from booko-services (ADR 0001). **Read from its docs and examples, not
from running it.** Source: `main` as of 2026-10-04; latest release v0.123.0
(2026-09-29). Doc paths below are under `wiki/docs/` in that repo. Once the
misc01 trial runs, confirm each fact against a real instance and note it here.

## Permissions

**It runs as a container that mounts `/var/run/docker.sock`.** Every example
compose file does (`examples/*/server/compose.yaml`). Docker socket access is
root on the host: anything that can use the socket can start a privileged
container with `/` mounted. So:

- **Write access to the deployments repo's watched branch is root on every
  host running doco-cd.** A commit is a deploy, and a compose file can request
  `privileged: true` or bind-mount `/`.
- **The doco-cd image is root on every host.** Pin it by tag and digest; never
  track `:latest`.

**The image is distroless and has no shell.** Scripts run as init containers,
sidecars, compose lifecycle hooks, or scheduled jobs inside deployed containers
(`Advanced/Pre-Post-Deployment-Scripts.md`), never in doco-cd itself.

**One instance can deploy to many hosts through Docker contexts**
(`Advanced/Docker-Contexts.md`), over TCP, TCP+TLS or SSH. Over SSH, the key
must be **passphrase-free** (Docker's SSH transport runs non-interactively),
and Docker doesn't try every key, so each host needs its key named. We don't use
this (see ADR 0001): a central instance would hold root-equivalent SSH access
to every host, and every host's age key.

## Destroy and volumes: the defaults differ

From `Deploy-Settings.md` and `Endpoints/REST-API.md`:

| Path | Removes volumes by default? |
|---|---|
| `destroy: true` (shorthand) | **Yes**: `remove_volumes`, `remove_images` and `remove_dir` all default to `true` |
| `destroy: {enabled: true, …}` (object) | Whatever `remove_volumes` says. Always write it out |
| `auto_discovery.delete: true` (stack dir removed from git) | No: `auto_discovery.remove_volumes` defaults to `false` |
| `DELETE /v1/api/project/{name}` | **Yes**: `volumes` defaults to `true`; pass `?volumes=false` |
| MCP tool `destroy_project` | Takes a `volumes` argument; default not stated |
| Docker Swarm mode | `remove_volumes` is always `true` |

Still undocumented: what happens when an entry is simply removed from
`.doco-cd.<host>.yml`.

## API

- Enabled by setting `API_SECRET` or `API_SECRET_FILE`, and authenticated with
  an `x-api-key` header. **There is one key, and it can do everything,**
  including `DELETE`.
- **Run history is in memory** (`/v1/api/runs`, `limit` max 200). A restart
  loses it, which is why Pedant keeps its own history.
- A poll run triggered through the API counts as a manual deployment for sync
  windows.
- Restart and recreate exist per project, and per service for recreate.
- `OPENAPI_ENABLED=true` exposes the OpenAPI spec. Use it to find out whether
  `/v1/api/project/{name}` returns image labels (an open question in ADR 0001).

## Built-in MCP server

doco-cd has its own MCP endpoint at `/mcp` (`Endpoints/MCP-Server.md`).

- **Off by default** (`MCP_ENABLED: false`).
- Uses the same all-powerful `x-api-key`.
- Its tools include deploy, stop, restart, scale and `destroy_project`, and the
  docs themselves warn that they're destructive.
- **Keep it off on our hosts.** Agents go through Pedant, which enforces "changes
  go through git" (ADR 0001) and never removes volumes. A doco-cd MCP endpoint
  would bypass both.

## Other features worth knowing about

- **Sync windows:** timezone-aware windows controlling when deploys may happen.
- **Cron-scheduled polling.**
- **Notifications** through Apprise, which can POST JSON to Pedant.
- **Prometheus metrics,** including MCP request metrics.
- **OCI artifacts** as a deploy source, as well as git.
- **Reconciliation:** event-driven, and it can restore workloads changed outside
  doco-cd.

## Check

```sh
gh api repos/kimdre/doco-cd/contents/wiki/docs/Deploy-Settings.md --jq .content | base64 -d | grep -n -A12 '### Destroy settings'
gh api repos/kimdre/doco-cd/contents/wiki/docs/Endpoints/REST-API.md --jq .content | base64 -d | grep -n 'DELETE\|in memory'
gh api repos/kimdre/doco-cd/contents/wiki/docs/Endpoints/MCP-Server.md --jq .content | base64 -d | grep -n 'MCP_ENABLED\|destroy'
gh api repos/kimdre/doco-cd/contents/examples/deployments-repo/server/compose.yaml --jq .content | base64 -d | grep docker.sock
```
