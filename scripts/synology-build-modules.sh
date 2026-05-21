#!/usr/bin/env bash
# Build binder_linux.ko and ashmem_linux.ko for a Synology DS224+ (or similar
# geminilake NAS) using Docker.
#
# Run this on the NAS itself (or on any x86_64 machine with Docker):
#   sudo bash scripts/synology-build-modules.sh
#
# The compiled .ko files land in  docker/modules/  and are picked up
# automatically by  scripts/synology-deploy.sh.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[✗]${NC} %s\n" "$*"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── Detect DSM build number ─────────────────────────────────────────────────
# Try to read from the NAS itself; fall back to a known-good default.

DSM_BUILD="${DSM_BUILD:-}"
if [[ -z "$DSM_BUILD" ]] && [[ -f /etc.defaults/VERSION ]]; then
  major=$(grep majorversion /etc.defaults/VERSION | cut -d'"' -f2)
  minor=$(grep minorversion /etc.defaults/VERSION | cut -d'"' -f2)
  build=$(grep buildnumber  /etc.defaults/VERSION | cut -d'"' -f2)
  if [[ -n "$major" && -n "$minor" && -n "$build" ]]; then
    DSM_BUILD="${major}.${minor}-${build}"
    info "Detected DSM $DSM_BUILD from /etc.defaults/VERSION"
  fi
fi

DSM_BUILD="${DSM_BUILD:-7.3-86009}"
PLATFORM="${PLATFORM:-geminilake}"

info "Building kernel modules for DSM $DSM_BUILD ($PLATFORM)"
info "This downloads ~500 MB of toolchain + kernel source. First run takes 10-20 min."
echo

# ── Verify Docker ────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  fail "Docker not found. Install Container Manager from DSM Package Center."
fi

# ── Build ────────────────────────────────────────────────────────────────────

MODULES_DIR="$ROOT/docker/modules"
mkdir -p "$MODULES_DIR"

IMAGE_TAG="synology-modules-${PLATFORM}:${DSM_BUILD}"

info "Building Docker image (this compiles the kernel modules)…"
docker build \
  --platform linux/amd64 \
  --build-arg DSM_BUILD="$DSM_BUILD" \
  --build-arg PLATFORM="$PLATFORM" \
  -t "$IMAGE_TAG" \
  -f docker/synology-modules.Dockerfile \
  docker/

info "Extracting .ko files…"
CONTAINER_ID=$(docker create "$IMAGE_TAG")
docker cp "$CONTAINER_ID:/out/binder_linux.ko" "$MODULES_DIR/"
docker cp "$CONTAINER_ID:/out/ashmem_linux.ko" "$MODULES_DIR/"
docker rm "$CONTAINER_ID" >/dev/null

# ── Verify ───────────────────────────────────────────────────────────────────

echo
info "Built modules:"
ls -lh "$MODULES_DIR"/binder_linux.ko "$MODULES_DIR"/ashmem_linux.ko

echo
info "Module vermagic:"
if command -v modinfo &>/dev/null; then
  modinfo "$MODULES_DIR/binder_linux.ko" 2>/dev/null | grep -E "^(filename|vermagic)" || true
  modinfo "$MODULES_DIR/ashmem_linux.ko" 2>/dev/null | grep -E "^(filename|vermagic)" || true
fi

# Check if the running kernel matches.
RUNNING_KERNEL=$(uname -r 2>/dev/null || echo "unknown")
echo
info "NAS kernel: $RUNNING_KERNEL"
warn "The vermagic in the .ko files must match the kernel above."
warn "If they don't match, override DSM_BUILD=x.x-xxxxx and rebuild."

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "  Modules ready in: $MODULES_DIR/"
echo
echo "  Next step — run the deploy script:"
echo "    sudo bash scripts/synology-deploy.sh"
echo "═══════════════════════════════════════════════════════════════════"
