#!/usr/bin/env bash
# Check prerequisites for headless-android on the current host.
set -u

GREEN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; NC='\033[0m'
ok() { printf "  ${GREEN}ok${NC}  %s\n" "$1"; }
bad(){ printf "  ${RED}MISS${NC} %s\n" "$1"; FAILED=$((FAILED+1)); }
warn(){ printf "  ${YEL}warn${NC} %s\n" "$1"; }

FAILED=0
echo "headless-android :: doctor"
echo

echo "host:"
echo "  os:   $(uname -s) $(uname -r)"
echo "  arch: $(uname -m)"
echo

echo "core tools:"
command -v node    >/dev/null && ok "node      ($(node -v))"        || bad "node 20+ (https://nodejs.org)"
command -v npm     >/dev/null && ok "npm       ($(npm -v))"          || bad "npm"
command -v adb     >/dev/null && ok "adb       ($(adb --version | head -1))" || bad "adb (install Android platform-tools)"
echo

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "macOS / AVD path:"
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  if [[ -d "$SDK" ]]; then
    ok "android sdk at $SDK"
  else
    bad "android sdk (install Android Studio or commandlinetools)"
  fi
  [[ -x "$SDK/emulator/emulator"          ]] && ok "emulator binary"      || bad "emulator binary ($SDK/emulator/emulator)"
  SDKMGR="$SDK/cmdline-tools/latest/bin/sdkmanager"
  AVDMGR="$SDK/cmdline-tools/latest/bin/avdmanager"
  [[ -x "$SDKMGR" ]] && ok "sdkmanager"  || bad "sdkmanager ($SDKMGR)"
  [[ -x "$AVDMGR" ]] && ok "avdmanager"  || bad "avdmanager ($AVDMGR)"
  IMG_DIR="$SDK/system-images/android-34/google_apis"
  if compgen -G "$IMG_DIR/*" >/dev/null; then
    ok "android-34 google_apis system image already installed"
  else
    warn "android-34 google_apis image not installed (avd-up.sh will fetch it)"
  fi
  echo
fi

echo "docker / redroid path (optional on macOS):"
if command -v docker >/dev/null; then
  ok "docker     ($(docker --version))"
  docker compose version >/dev/null 2>&1 && ok "docker compose" || warn "docker compose plugin not detected"
else
  warn "docker not installed (only needed for Redroid backend)"
fi
echo

if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}$FAILED required tool(s) missing.${NC}"
  exit 1
fi
echo -e "${GREEN}all required tools present.${NC}"
