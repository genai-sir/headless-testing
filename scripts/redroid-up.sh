#!/usr/bin/env bash
# Bring up the Linux/Redroid stack via docker compose.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "warning: Redroid expects a Linux host with binder/ashmem modules."
  echo "         On macOS, Docker Desktop runs a Linux VM that DOES NOT have these"
  echo "         modules. Prefer scripts/avd-up.sh on macOS."
  echo
fi

# Check kernel modules on Linux.
if [[ "$(uname -s)" == "Linux" ]]; then
  for mod in binder_linux ashmem_linux; do
    if ! lsmod | grep -q "^$mod"; then
      echo "kernel module '$mod' is not loaded."
      echo "install redroid-modules DKMS for your distro:"
      echo "  https://github.com/remote-android/redroid-doc/wiki/Run-redroid-with-systemd"
      exit 1
    fi
  done
fi

docker compose -f docker/docker-compose.yml up -d --build

echo
echo "waiting for adb to see redroid…"
for i in $(seq 1 60); do
  if docker exec headless-backend adb devices 2>/dev/null | grep -q "redroid:5555\sdevice"; then
    echo "  online."
    break
  fi
  sleep 2
done

echo
echo "==> ready"
echo "  dashboard:  http://localhost:3000"
echo "  ws-scrcpy:  http://localhost:8000"
echo "  adb host:   adb connect localhost:5555"
echo "  stop with:  scripts/redroid-down.sh"
