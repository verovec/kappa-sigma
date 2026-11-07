#!/usr/bin/env bash
# The three live S3 suites against one endpoint (card 0183): RemoteKit's round trip, the Export
# stage, and a night stacked from a bucket. They run here only (ASTROSTACK_S3_LIVE=1): an endpoint
# left in `.env` never turns them on inside `just check`.
#
# A loopback endpoint gets a local MinIO first (`s3-minio.sh`) and MinIO's own keys and bucket,
# whatever `.env` names for a real one. Any other endpoint is used as given, with the keys, region
# and bucket of the environment (`.env`: ASTROSTACK_S3_LIVE_*); the suites write and delete under
# `astrostack-live/<day>-<id>/` of that bucket, and create it only if the service says it is missing.
#
# Usage: s3-live.sh <package dir> <endpoint or ""> [swift test flags…]; an empty endpoint is
# ASTROSTACK_S3_LIVE_ENDPOINT, else the local MinIO.
set -euo pipefail
pkg="$1"
endpoint="${2:-${ASTROSTACK_S3_LIVE_ENDPOINT:-http://127.0.0.1:9000}}"
shift 2

case "$endpoint" in
  http://127.0.0.1:* | http://localhost:*)
    port="${endpoint##*:}"
    "$(dirname "$0")/s3-minio.sh" "${port%%/*}"
    unset ASTROSTACK_S3_LIVE_ACCESS_KEY ASTROSTACK_S3_LIVE_SECRET_KEY ASTROSTACK_S3_LIVE_BUCKET \
      ASTROSTACK_S3_LIVE_REGION ASTROSTACK_S3_LIVE_ADDRESSING
    ;;
  http://* | https://*) ;;
  *)
    echo "s3-live: '$endpoint' is not an http(s) URL (e.g. http://127.0.0.1:9000)" >&2
    exit 2
    ;;
esac
cd "$pkg"
ASTROSTACK_S3_LIVE=1 ASTROSTACK_S3_LIVE_ENDPOINT="$endpoint" exec swift test "$@" --no-parallel \
  --filter 'LiveS3Tests|LiveExportS3Tests|RemotePipelineLiveTests'
