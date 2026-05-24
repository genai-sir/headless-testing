#!/usr/bin/env bash
# Restore a redroid /data snapshot created by snapshot-redroid-data.sh.
# WARNING: this wipes the current volume before extracting.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <path-to-tar.zst>" >&2
  exit 1
fi

SNAP="$1"
[[ -f "$SNAP" ]] || { echo "no such file: $SNAP" >&2; exit 1; }

VOLUME="${REDROID_VOLUME:-docker_redroid-data}"

echo "==> stopping redroid container if present"
docker stop headless-redroid 2>/dev/null || true

echo "==> wiping volume $VOLUME"
docker volume rm "$VOLUME" 2>/dev/null || true
docker volume create "$VOLUME" >/dev/null

echo "==> extracting $(basename "$SNAP")"
docker run --rm \
  -v "$VOLUME":/data \
  -v "$(cd "$(dirname "$SNAP")" && pwd)":/snap:ro \
  alpine sh -c "
    apk add --no-cache zstd >/dev/null
    cd / && zstd -dc /snap/$(basename "$SNAP") | tar -xf - data
  "

echo "done. start redroid: docker compose -f docker/docker-compose.yml up -d redroid"
