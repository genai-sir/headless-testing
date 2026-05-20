#!/usr/bin/env bash
# Stop everything started by avd-up.sh.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="$ROOT/.run"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
EMU_PORT="${EMU_PORT:-5554}"
ADB_SERIAL="emulator-${EMU_PORT}"

stop_pid() {
  local name="$1" pidfile="$PID_DIR/$1.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      echo "stopping $name (pid $pid)"
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  fi
}

stop_pid backend
stop_pid ws-scrcpy

if "$SDK/platform-tools/adb" devices 2>/dev/null | grep -q "^${ADB_SERIAL}\s"; then
  echo "stopping emulator $ADB_SERIAL"
  "$SDK/platform-tools/adb" -s "$ADB_SERIAL" emu kill || true
fi
stop_pid emulator

echo "down."
