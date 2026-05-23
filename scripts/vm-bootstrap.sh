#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu Server VM (22.04 / 24.04) into a working
# headless-android Redroid host.
#
# Intended to be run inside the VM, NOT on the Synology host. The point of
# this path: DSM's kernel doesn't ship binder/ashmem, but a normal Ubuntu
# kernel running inside Synology VMM does, and DKMS builds the modules
# against it cleanly.
#
# Run as root (or with sudo):
#   curl -fsSL https://raw.githubusercontent.com/genai-sir/headless-testing/main/scripts/vm-bootstrap.sh | sudo bash
# or, if you've already cloned the repo:
#   sudo bash scripts/vm-bootstrap.sh
#
# Exposes these on the VM's IP (visible on your LAN via VMM bridged networking):
#   :3000  dashboard
#   :8000  ws-scrcpy
#   :5555  adb
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/genai-sir/headless-testing.git}"
REPO_DIR="${REPO_DIR:-/opt/headless-android}"
BRANCH="${BRANCH:-main}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script is for the Linux VM only. On macOS, use scripts/avd-up.sh." >&2
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Re-running with sudo…"
  exec sudo -E bash "$0" "$@"
fi

step() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }

# ---------------------------------------------------------------------------
step "sanity"
. /etc/os-release 2>/dev/null || true
echo "  OS:     ${PRETTY_NAME:-unknown}"
echo "  kernel: $(uname -r)"
echo "  arch:   $(uname -m)"
if ! grep -qE '^(ubuntu|debian)' <<<"${ID:-}${ID_LIKE:-}"; then
  echo "  WARNING: this script targets Debian/Ubuntu. Continuing anyway…"
fi

# ---------------------------------------------------------------------------
step "apt prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release \
  git build-essential dkms "linux-headers-$(uname -r)" \
  android-tools-adb

# ---------------------------------------------------------------------------
step "docker engine + compose plugin"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker --version
docker compose version

# ---------------------------------------------------------------------------
step "binder + ashmem kernel modules (DKMS)"
# anbox-modules ships exactly the two modules redroid needs and builds cleanly
# against mainline Ubuntu kernels. The remote-android/redroid-modules repo is
# what redroid's own docs point at.
MOD_SRC=/usr/src/redroid-modules
if [[ ! -d "$MOD_SRC" ]]; then
  git clone --depth 1 https://github.com/remote-android/redroid-modules.git "$MOD_SRC"
fi
if ! lsmod | grep -q '^binder_linux'; then
  echo "  building binder_linux + ashmem_linux via DKMS…"
  (cd "$MOD_SRC" && dkms install . || dkms build . && dkms install .)
  # Try the modaliases redroid-modules registers under.
  modprobe binder_linux  num_binder_devices=128 || true
  modprobe ashmem_linux || true
fi

# Persist across reboot.
cat > /etc/modules-load.d/redroid.conf <<'EOF'
ashmem_linux
binder_linux
EOF
cat > /etc/modprobe.d/redroid.conf <<'EOF'
options binder_linux num_binder_devices=128
EOF

step "verify modules are loaded"
LOADED_OK=1
for mod in binder_linux ashmem_linux; do
  if lsmod | grep -q "^$mod"; then
    echo "  loaded: $mod"
  else
    echo "  MISSING: $mod  — check 'dmesg | tail -50' and the DKMS build log."
    LOADED_OK=0
  fi
done
if [[ $LOADED_OK -ne 1 ]]; then
  echo "Kernel modules failed to load. Cannot start Redroid." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
step "clone or update project"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
else
  (cd "$REPO_DIR" && git pull --ff-only origin "$BRANCH" || true)
fi
chown -R "$SUDO_USER:$SUDO_USER" "$REPO_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
step "bring up the docker compose stack"
cd "$REPO_DIR"
docker compose -f docker/docker-compose.yml up -d --build

echo
echo "waiting for adb to see redroid (up to 90s)…"
for i in $(seq 1 45); do
  if docker exec headless-backend adb devices 2>/dev/null | grep -qE 'redroid:5555\s+device'; then
    echo "  online after ${i}×2s."
    break
  fi
  sleep 2
done

# ---------------------------------------------------------------------------
step "ready"
IP="$(hostname -I | awk '{print $1}')"
cat <<EOF

  dashboard:   http://${IP}:3000
  ws-scrcpy:   http://${IP}:8000
  adb host:    adb connect ${IP}:5555

  stop:        cd $REPO_DIR && sudo docker compose -f docker/docker-compose.yml down
  restart:     cd $REPO_DIR && sudo docker compose -f docker/docker-compose.yml up -d
  logs:        sudo docker compose -f $REPO_DIR/docker/docker-compose.yml logs -f

  Next steps from your Mac browser:
    open http://${IP}:3000
    (sideload APKs, set mock GPS, etc.)
EOF
