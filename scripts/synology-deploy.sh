#!/usr/bin/env bash
# Deploy headless-android on a Synology NAS (Intel-based, DSM 7.x).
#
# Prerequisites:
#   - Intel/AMD CPU (x86_64) — ARM NAS models won't work with redroid
#   - DSM 7.x with Container Manager installed
#   - SSH enabled: Control Panel → Terminal & SNMP → Enable SSH
#
# Run this script as root on the NAS:
#   sudo bash scripts/synology-deploy.sh
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[✗]${NC} %s\n" "$*"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── 1. Preflight checks ─────────────────────────────────────────────────────

[[ "$(uname -m)" == "x86_64" ]] || fail "Redroid requires x86_64. This machine is $(uname -m)."
[[ "$(uname -s)" == "Linux" ]]  || fail "This script must run on the Synology NAS (Linux), not macOS."

if [[ $EUID -ne 0 ]]; then
  fail "Run as root:  sudo bash $0"
fi

if ! command -v docker &>/dev/null; then
  fail "Docker not found. Install Container Manager from DSM Package Center."
fi

if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
  fail "Docker Compose not available. Update Container Manager in DSM Package Center."
fi

# Prefer 'docker compose' (plugin) over standalone 'docker-compose'.
if docker compose version &>/dev/null; then
  COMPOSE="docker compose"
else
  COMPOSE="docker-compose"
fi

info "Docker OK: $(docker --version)"
info "Compose OK: $($COMPOSE version)"

# ── 2. Kernel modules (binder + ashmem) ─────────────────────────────────────

MODULES_OK=true
MODULES_DIR="$ROOT/docker/modules"

load_module() {
  local mod="$1"
  if lsmod | grep -q "^${mod}"; then
    info "Kernel module '$mod' already loaded."
    return 0
  fi

  warn "Module '$mod' not loaded — attempting modprobe…"
  if modprobe "$mod" 2>/dev/null; then
    info "Loaded '$mod' via modprobe."
    return 0
  fi

  # Try the pre-built .ko from docker/modules/ (compiled by synology-build-modules.sh).
  if [[ -f "$MODULES_DIR/${mod}.ko" ]]; then
    warn "Found $MODULES_DIR/${mod}.ko — loading with insmod…"
    if insmod "$MODULES_DIR/${mod}.ko" devices="binder,hwbinder,vndbinder" 2>/dev/null \
    || insmod "$MODULES_DIR/${mod}.ko" 2>/dev/null; then
      info "Loaded '$mod' from pre-built module."
      return 0
    else
      printf "${RED}[✗]${NC} insmod failed for %s (vermagic mismatch?).\n" "$MODULES_DIR/${mod}.ko"
    fi
  fi

  # Check /lib/modules as last resort.
  local ko
  ko=$(find /lib/modules -name "${mod}.ko" 2>/dev/null | head -1)
  if [[ -n "$ko" ]]; then
    warn "Found $ko — loading with insmod…"
    if insmod "$ko" 2>/dev/null; then
      info "Loaded '$mod' via insmod."
      return 0
    fi
  fi

  return 1
}

for mod in binder_linux ashmem_linux; do
  if ! load_module "$mod"; then
    MODULES_OK=false
    printf "${RED}[✗]${NC} Could not load kernel module '%s'.\n" "$mod"
  fi
done

if [[ "$MODULES_OK" != "true" ]]; then
  # Check if we have the build script and offer to compile automatically.
  if [[ -f "$ROOT/scripts/synology-build-modules.sh" ]] && [[ ! -f "$MODULES_DIR/binder_linux.ko" ]]; then
    echo
    warn "Kernel modules not found. Compiling them from Synology GPL source…"
    warn "This downloads ~500 MB and takes 10-20 min (first time only)."
    echo
    bash "$ROOT/scripts/synology-build-modules.sh"

    # Retry loading after build.
    MODULES_OK=true
    for mod in binder_linux ashmem_linux; do
      if ! lsmod | grep -q "^${mod}"; then
        if [[ -f "$MODULES_DIR/${mod}.ko" ]]; then
          insmod "$MODULES_DIR/${mod}.ko" devices="binder,hwbinder,vndbinder" 2>/dev/null \
          || insmod "$MODULES_DIR/${mod}.ko" 2>/dev/null \
          || { MODULES_OK=false; printf "${RED}[✗]${NC} insmod failed for '%s' after build.\n" "$mod"; }
        else
          MODULES_OK=false
        fi
      fi
    done
  fi

  if [[ "$MODULES_OK" != "true" ]]; then
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  The kernel modules binder_linux / ashmem_linux could not be"
    echo "  loaded. The compiled .ko vermagic may not match your kernel."
    echo
    echo "  Your kernel: $(uname -r)"
    echo
    echo "  Try rebuilding with your exact DSM build number:"
    echo "    DSM_BUILD=x.x-xxxxx sudo bash scripts/synology-build-modules.sh"
    echo
    echo "  Find your DSM build: cat /etc.defaults/VERSION"
    echo "═══════════════════════════════════════════════════════════════════"
    exit 1
  fi
fi

# Ensure modules survive a NAS reboot.
TASK_CONF="/usr/local/etc/rc.d/redroid-modules.sh"
info "Creating boot script to auto-load modules on reboot…"
cat > "$TASK_CONF" <<BOOT
#!/bin/sh
# Load kernel modules needed by Redroid on every DSM boot.
modprobe binder_linux 2>/dev/null \\
  || insmod ${MODULES_DIR}/binder_linux.ko devices="binder,hwbinder,vndbinder" 2>/dev/null \\
  || true
modprobe ashmem_linux 2>/dev/null \\
  || insmod ${MODULES_DIR}/ashmem_linux.ko 2>/dev/null \\
  || true
BOOT
chmod 755 "$TASK_CONF"
info "Created $TASK_CONF"

# ── 3. Detect NAS LAN IP ────────────────────────────────────────────────────

NAS_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' || hostname -I | awk '{print $1}')
info "Detected NAS IP: $NAS_IP"

# ── 4. Deploy with Docker Compose ───────────────────────────────────────────

info "Building and starting services…"
$COMPOSE -f docker/docker-compose.yml up -d --build

echo
info "Waiting for redroid to become reachable via adb…"
for i in $(seq 1 90); do
  if docker exec headless-backend adb devices 2>/dev/null | grep -q "redroid:5555.*device"; then
    info "Redroid is online."
    break
  fi
  if [[ $i -eq 90 ]]; then
    warn "Redroid did not come up in 3 minutes. Check: docker logs headless-redroid"
  fi
  sleep 2
done

# ── 5. Done ──────────────────────────────────────────────────────────────────

echo
echo "═══════════════════════════════════════════════════════════════════"
echo "  headless-android is running on your Synology NAS"
echo
echo "  Dashboard:   http://${NAS_IP}:3000"
echo "  ws-scrcpy:   http://${NAS_IP}:8000"
echo "  adb:         adb connect ${NAS_IP}:5555"
echo
echo "  Stop:        sudo $COMPOSE -f $ROOT/docker/docker-compose.yml down"
echo "  Logs:        docker logs -f headless-backend"
echo "═══════════════════════════════════════════════════════════════════"
