#!/usr/bin/env bash
# Bring up the macOS AVD path:
#   1. Ensure android-34 google_apis system image (rooted) is installed
#   2. Create the headless-pixel AVD if absent
#   3. Start the emulator headless with -writable-system
#   4. Wait for boot, run `adb root`, flip mock-location appop
#   5. Install ws-scrcpy in ./.ws-scrcpy if missing, start it on :8000
#   6. Start the dashboard backend on :3000
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/platform-tools:$SDK/emulator:$SDK/cmdline-tools/latest/bin:$PATH"

AVD_NAME="${AVD_NAME:-headless-pixel}"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  PKG_ABI="arm64-v8a"
else
  PKG_ABI="x86_64"
fi
SYSIMG="system-images;android-34;google_apis;${PKG_ABI}"
PLATFORM="platforms;android-34"
DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_6}"
EMU_PORT="${EMU_PORT:-5554}"
ADB_SERIAL="emulator-${EMU_PORT}"
WS_SCRCPY_DIR="$ROOT/.ws-scrcpy"
PID_DIR="$ROOT/.run"
mkdir -p "$PID_DIR"

echo "==> doctor"
bash "$ROOT/scripts/doctor.sh"

echo
echo "==> ensuring SDK packages"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" "emulator" "$PLATFORM" "$SYSIMG"

echo
echo "==> creating AVD '$AVD_NAME' if needed"
if ! "$SDK/cmdline-tools/latest/bin/avdmanager" list avd | grep -q "Name: $AVD_NAME"; then
  echo "no" | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd \
    -n "$AVD_NAME" -k "$SYSIMG" -d "$DEVICE_PROFILE" --force
  AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
  AVD_CFG="$AVD_HOME/${AVD_NAME}.avd/config.ini"
  {
    echo "hw.ramSize=4096"
    echo "vm.heapSize=512"
    echo "disk.dataPartition.size=8G"
    echo "hw.gps=yes"
    echo "hw.keyboard=yes"
  } >> "$AVD_CFG"
else
  echo "  exists."
fi

echo
echo "==> launching emulator on port $EMU_PORT (headless, writable-system)"
LOG="$PID_DIR/emulator.log"
if "$SDK/platform-tools/adb" devices | grep -q "^${ADB_SERIAL}\s"; then
  echo "  $ADB_SERIAL already running."
else
  nohup "$SDK/emulator/emulator" \
    -avd "$AVD_NAME" \
    -port "$EMU_PORT" \
    -no-snapshot-save \
    -writable-system \
    -no-audio \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    -no-window \
    > "$LOG" 2>&1 &
  echo $! > "$PID_DIR/emulator.pid"
  echo "  pid $(cat "$PID_DIR/emulator.pid") · log $LOG"
fi

echo
echo "==> waiting for boot (up to 3 min)"
"$SDK/platform-tools/adb" -s "$ADB_SERIAL" wait-for-device
for i in $(seq 1 180); do
  if [[ "$("$SDK/platform-tools/adb" -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    echo "  booted."
    break
  fi
  sleep 1
done

echo
echo "==> adb root"
"$SDK/platform-tools/adb" -s "$ADB_SERIAL" root || true
sleep 2
"$SDK/platform-tools/adb" -s "$ADB_SERIAL" wait-for-device

echo
echo "==> clear the legacy 'Allow mock locations' flag"
# Older guides set this to 1, but on API 23+ Android ignores it. Apps still
# read it as a detection signal — keeping it 0 is the stealth-friendly state.
# Per-app mock-loc grants happen via `cmd appops set ... mock_location allow`.
"$SDK/platform-tools/adb" -s "$ADB_SERIAL" shell settings put secure mock_location 0 || true

echo
echo "==> ws-scrcpy"
if [[ ! -d "$WS_SCRCPY_DIR" ]]; then
  echo "  cloning ws-scrcpy into $WS_SCRCPY_DIR"
  git clone --depth 1 https://github.com/NetrisTV/ws-scrcpy.git "$WS_SCRCPY_DIR"
  (cd "$WS_SCRCPY_DIR" && npm install --silent)
fi
WS_LOG="$PID_DIR/ws-scrcpy.log"
if [[ -f "$PID_DIR/ws-scrcpy.pid" ]] && kill -0 "$(cat "$PID_DIR/ws-scrcpy.pid")" 2>/dev/null; then
  echo "  already running (pid $(cat "$PID_DIR/ws-scrcpy.pid"))"
else
  nohup bash -c "cd '$WS_SCRCPY_DIR' && npm start" > "$WS_LOG" 2>&1 &
  echo $! > "$PID_DIR/ws-scrcpy.pid"
  echo "  pid $(cat "$PID_DIR/ws-scrcpy.pid") · log $WS_LOG"
fi

echo
echo "==> backend"
(cd "$ROOT/backend" && npm install --silent)
BE_LOG="$PID_DIR/backend.log"
if [[ -f "$PID_DIR/backend.pid" ]] && kill -0 "$(cat "$PID_DIR/backend.pid")" 2>/dev/null; then
  echo "  already running (pid $(cat "$PID_DIR/backend.pid"))"
else
  ADB_SERIAL="$ADB_SERIAL" BACKEND_TYPE=avd \
    nohup node "$ROOT/backend/server.js" > "$BE_LOG" 2>&1 &
  echo $! > "$PID_DIR/backend.pid"
  echo "  pid $(cat "$PID_DIR/backend.pid") · log $BE_LOG"
fi

sleep 1
echo
echo "==> ready"
echo "  dashboard:  http://127.0.0.1:3000"
echo "  ws-scrcpy:  http://localhost:8000"
echo "  stop with:  scripts/avd-down.sh"
