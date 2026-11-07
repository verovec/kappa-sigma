#!/usr/bin/env bash
# The three live S3 suites against one endpoint (card 0183): RemoteKit's round trip, the Export
# stage, and a night stacked from a bucket. A loopback endpoint gets a local MinIO first
# (`s3-minio.sh`); any other endpoint is used as given, with the keys and bucket of the
# environment (`.env`: ASTROSTACK_S3_LIVE_*), and is never started or created here.
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
    ;;
esac
cd "$pkg"
ASTROSTACK_S3_LIVE_ENDPOINT="$endpoint" exec swift test "$@" --no-parallel \
  --filter 'LiveS3Tests|LiveExportS3Tests|RemotePipelineLiveTests'
