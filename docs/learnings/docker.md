# Docker

Facts about reading container state, as Pedant's SSH inventory does. Verified
with a throwaway busybox container on 2026-10-04.

## Facts

**`docker inspect` returns environment variables in plaintext, secrets
included.** `.Config.Env` holds every `-e` / `env_file` value as `NAME=value`.
Anything that stores raw `docker inspect` output stores the host's secrets.

**`docker ps --format '{{json .}}'` doesn't include the environment.** Its
fields are `Command, CreatedAt, HealthStatus, ID, Image, Labels, LocalVolumes,
Mounts, Names, Networks, Platform, Ports, RunningFor, Size, State, Status`.
`Labels` includes the labels a container inherits from its image, so the
`org.opencontainers.image.version` / `.revision` labels are available from
`docker ps` alone. (Verified 2026-10-04 against Pedant's own image, which sets
them in its Dockerfile.)

**`docker inspect --format` selects fields on the host**, so fields left out
never cross the SSH connection. Prefer
`docker inspect --format '{{json .Config.Labels}} {{.Image}}' …` to a full
`docker inspect` that gets filtered afterwards.

## Check

```sh
docker run -d --rm --name envtest -e API_TOKEN=s3cret busybox sleep 30
docker inspect --format '{{json .Config.Env}}' envtest      # shows API_TOKEN=s3cret
docker ps --filter name=envtest --format '{{json .}}'       # no Env field
docker rm -f envtest

# inherited image labels show in docker ps (any image with LABELs)
docker run -d --rm --name labeltest --entrypoint sleep <labelled-image> 30
docker ps --filter name=labeltest --format '{{.Labels}}'
docker rm -f labeltest
```
