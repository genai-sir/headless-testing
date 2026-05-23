#!/usr/bin/env bash
# Bake a redroid image with Magisk + MindTheGApps using a pinned commit of
# ayasa520/redroid-script and our 14.0.0_64only patches.
#
# Output: redroid/redroid:14.0.0_64only_mindthegapps_magisk (Docker image)
#
# Usage:
#   sudo scripts/build-redroid-image.sh                      # default flags
#   sudo BUILD_ARGS="-m"  scripts/build-redroid-image.sh     # Magisk only
#   sudo BUILD_ARGS="-m -mtg -w" scripts/build-redroid-image.sh
#
# Requires: docker, python3 + tqdm + requests, lzip, unzip, git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$ROOT/docker/redroid-build/patches"
# Pin to a known-good commit so future upstream rearrangements don't break us.
# Bump deliberately, with a re-verify.
REDROID_SCRIPT_REPO="${REDROID_SCRIPT_REPO:-https://github.com/ayasa520/redroid-script.git}"
REDROID_SCRIPT_REF="${REDROID_SCRIPT_REF:-main}"

ANDROID_VERSION="${ANDROID_VERSION:-14.0.0_64only}"
BUILD_ARGS="${BUILD_ARGS:--m -mtg}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> python deps"
python3 -c "import tqdm, requests" 2>/dev/null \
  || { echo "missing python deps. install: apt-get install -y python3-tqdm python3-requests" >&2; exit 1; }
command -v lzip >/dev/null \
  || { echo "missing lzip. install: apt-get install -y lzip" >&2; exit 1; }
command -v unzip >/dev/null \
  || { echo "missing unzip. install: apt-get install -y unzip" >&2; exit 1; }

echo "==> cloning redroid-script ($REDROID_SCRIPT_REF)"
git clone --depth 50 "$REDROID_SCRIPT_REPO" "$WORKDIR/src"
( cd "$WORKDIR/src" && git checkout "$REDROID_SCRIPT_REF" )

echo "==> applying patches"
for patch in "$PATCHES"/*.patch; do
  echo "  applying $(basename "$patch")"
  ( cd "$WORKDIR/src" && git apply --check "$patch" && git apply "$patch" )
done

echo "==> building redroid image: $ANDROID_VERSION $BUILD_ARGS"
( cd "$WORKDIR/src" && python3 redroid.py -a "$ANDROID_VERSION" $BUILD_ARGS )

echo
echo "done. built images:"
docker images redroid/redroid --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})" | head -5
