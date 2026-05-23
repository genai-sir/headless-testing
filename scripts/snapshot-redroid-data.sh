#!/usr/bin/env bash
# Snapshot the redroid /data volume to a zstd-compressed tarball.
# Output goes to docker/backups/redroid-data-<timestamp>.tar.zst (gitignored).
#
# Restore with: scripts/restore-redroid-data.sh <path-to-tarball>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP_DIR="$ROOT/docker/backups"
mkdir -p "$SNAP_DIR"

VOLUME="${REDROID_VOLUME:-docker_redroid-data}"
DATE="$(date +%Y%m%d-%H%M%S)"
TARGET="$SNAP_DIR/redroid-data-$DATE.tar.zst"

if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "volume '$VOLUME' not found. set REDROID_VOLUME to override." >&2
  exit 1
fi

echo "==> snapshotting $VOLUME -> $TARGET"
docker run --rm \
  -v "$VOLUME":/data:ro \
  -v "$SNAP_DIR":/out \
  alpine sh -c "
    apk add --no-cache zstd >/dev/null
    cd / && tar -cf - data | zstd -3 -o /out/$(basename "$TARGET")
  "

echo "==> verifying"
docker run --rm -v "$SNAP_DIR":/snap:ro alpine sh -c "
  apk add --no-cache zstd >/dev/null
  zstd -t /snap/$(basename "$TARGET")
"

ls -lh "$TARGET"
echo "done."
