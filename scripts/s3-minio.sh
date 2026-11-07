#!/usr/bin/env bash
# Starts the local MinIO `just s3-live` runs against (card 0183), in Docker, on 127.0.0.1:<port>,
# one container per port (`astrostack-minio-<port>`). Does nothing when a server already answers
# there, and never removes a running container: another session's suites may be using it. A
# stopped Docker daemon is said, never worked around: there is no second server to fall back to.
#
# Image: MinIO no longer publishes `minio/minio` on Docker Hub and quay.io asks for a login
# (checked 2026-11-07), so this is Bitnami's frozen MinIO build, pinned by tag. Test data only:
# the container keeps nothing (`--rm`, no volume) and listens on loopback alone.
set -euo pipefail
port="${1:-9000}"
name="astrostack-minio-${port}"
image=bitnamilegacy/minio:2025.5.24
health="http://127.0.0.1:${port}/minio/health/live"

answers() {
  for _ in $(seq 1 "$1"); do
    curl -fsS "$health" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

if answers 1; then
  echo "s3-minio: a server already answers on 127.0.0.1:${port}"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "s3-minio: the Docker daemon is not running: start Docker Desktop (open -a Docker), then retry" >&2
  exit 1
fi
if [ -z "$(docker ps -q --filter "name=^${name}\$")" ]; then
  docker run -d --rm --name "$name" -p "127.0.0.1:${port}:9000" \
    -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin "$image" >/dev/null
fi
if answers 60; then
  echo "s3-minio: $image up on 127.0.0.1:${port} (minioadmin / minioadmin)"
  exit 0
fi
echo "s3-minio: no answer from $health within 60 s (docker logs $name)" >&2
exit 1
