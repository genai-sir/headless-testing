#!/usr/bin/env bash
# Install Magisk + LSPosed (Zygisk) inside the headless-pixel AVD using rootAVD.
#
# What this does, in order:
#   1. Clones rootAVD (https://gitlab.com/newbit/rootAVD) into .rootavd/
#   2. Patches the AVD's ramdisk.img to include Magisk
#   3. Stops the emulator, restarts it; the device now has /sbin/magisk
#   4. Downloads the LSPosed Zygisk module and the Manager APK
#   5. Pushes the Zygisk module into /data/adb/modules, installs the Manager APK
#   6. Builds & installs the stealth module (mock-location-helper)
#   7. Reboots so all hooks load
#
# After this:
#   - Open LSPosed Manager on device (via scrcpy), enable
#     "headless-android stealth", set scope on the apps you care about.
#   - Reboot again (the script does the first one; you do per-scope changes).
#
# Tested on Apple Silicon arm64 AVDs running google_apis;android-34.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

AVD_NAME="${AVD_NAME:-headless-pixel}"
EMU_PORT="${EMU_PORT:-5554}"
ADB_SERIAL="emulator-${EMU_PORT}"
ARCH="$(uname -m)"

ROOTAVD_DIR="$ROOT/.rootavd"
WORK="$ROOT/.run/magisk"
mkdir -p "$WORK"

echo "==> sanity"
adb -s "$ADB_SERIAL" get-state >/dev/null 2>&1 \
  || { echo "AVD '$ADB_SERIAL' is not running. start it with scripts/avd-up.sh first."; exit 1; }

# ---- 1. Magisk via rootAVD (skipped if already installed) ----
adb -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
sleep 1
if adb -s "$ADB_SERIAL" shell 'ls /data/adb/magisk' >/dev/null 2>&1; then
  echo
  echo "==> Magisk already installed, skipping rootAVD step."
else
  echo
  echo "==> rootAVD clone"
  if [[ ! -d "$ROOTAVD_DIR" ]]; then
    git clone --depth 1 https://gitlab.com/newbit/rootAVD.git "$ROOTAVD_DIR"
  else
    (cd "$ROOTAVD_DIR" && git pull --ff-only) || true
  fi

  echo
  echo "==> patch ramdisk (will stop the emulator)"
  if [[ "$ARCH" == "arm64" ]]; then
    RAMDISK_REL="system-images/android-34/google_apis/arm64-v8a/ramdisk.img"
  else
    RAMDISK_REL="system-images/android-34/google_apis/x86_64/ramdisk.img"
  fi
  (cd "$ROOTAVD_DIR" && ./rootAVD.sh "$RAMDISK_REL")

  echo
  echo "==> restart emulator"
  adb -s "$ADB_SERIAL" emu kill 2>/dev/null || true
  sleep 2
  scripts/avd-up.sh

  echo
  echo "==> wait for boot"
  for i in $(seq 1 120); do
    if [[ "$(adb -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      break
    fi
    sleep 1
  done
  adb -s "$ADB_SERIAL" root || true
  sleep 2
  adb -s "$ADB_SERIAL" wait-for-device

  echo
  echo "==> verify Magisk is present"
  if ! adb -s "$ADB_SERIAL" shell 'ls /data/adb/magisk' >/dev/null 2>&1; then
    echo "Magisk not detected at /data/adb/magisk after reboot."
    echo "Check rootAVD output above; common fix: re-run rootAVD with"
    echo "  $ROOTAVD_DIR/rootAVD.sh ListAllAVDs"
    echo "and pick the exact ramdisk for your AVD."
    exit 1
  fi
fi

# ---- 2. Resolve latest LSPosed zygisk release URL dynamically ----
# JingMatrix renamed the LSPosed repo to "Vector"; release assets still link
# back to the LSPosed namespace through the redirect, but new builds also
# publish a Vector-named release. We grep for the most-recent "LSPosed-*-zygisk-release.zip"
# asset across all releases so this survives further renames.
echo
echo "==> resolving latest LSPosed zygisk release"
LS_URL="${LSPOSED_ZYGISK_URL:-}"
if [[ -z "$LS_URL" ]]; then
  LS_URL="$(curl -sfL "https://api.github.com/repos/JingMatrix/LSPosed/releases?per_page=20" \
    | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    for a in r.get('assets', []):
        n = a.get('name', '')
        if n.startswith('LSPosed-') and n.endswith('-zygisk-release.zip'):
            print(a['browser_download_url']); sys.exit(0)
")"
fi
if [[ -z "$LS_URL" ]]; then
  echo "could not resolve an LSPosed zygisk release asset. Set LSPOSED_ZYGISK_URL manually."
  exit 1
fi
echo "  using: $LS_URL"

echo
echo "==> fetch LSPosed zip"
LS_ZIP="$WORK/lsposed-zygisk.zip"
if [[ ! -f "$LS_ZIP" ]] || [[ ! -s "$LS_ZIP" ]]; then
  rm -f "$LS_ZIP"
  curl -fL "$LS_URL" -o "$LS_ZIP"
fi

# ---- 3. Ensure /data/adb/magisk/ has support files ----
# rootAVD's bundled Magisk APK is a stub that triggers an on-device download
# of the full APK on first launch — but if the user never opened the Magisk
# app, /data/adb/magisk/ stays empty and `magisk --install-module` returns
# "Incomplete Magisk install". We seed it ourselves from the full APK that
# rootAVD also ships in Apps/Magisk.apk.
echo
echo "==> ensure /data/adb/magisk/ is populated"
NEEDS_SEED=0
adb -s "$ADB_SERIAL" shell 'su -c "test -f /data/adb/magisk/util_functions.sh"' >/dev/null 2>&1 \
  || NEEDS_SEED=1
if [[ $NEEDS_SEED -eq 1 ]]; then
  FULL_APK="$ROOTAVD_DIR/Apps/Magisk.apk"
  if [[ ! -f "$FULL_APK" ]]; then
    echo "Magisk APK not found at $FULL_APK — was rootAVD ever run?"
    exit 1
  fi
  STAGE="$WORK/stage"; FLAT="$WORK/flat"
  rm -rf "$STAGE" "$FLAT"; mkdir -p "$STAGE" "$FLAT"
  unzip -o "$FULL_APK" \
    'assets/util_functions.sh' 'assets/boot_patch.sh' 'assets/addon.d.sh' \
    'assets/module_installer.sh' 'assets/uninstaller.sh' \
    "lib/arm64-v8a/lib*.so" "lib/x86_64/lib*.so" \
    -d "$STAGE" >/dev/null
  cp "$STAGE/assets/"*.sh "$FLAT/"
  ABI_DIR="$STAGE/lib/arm64-v8a"
  [[ "$ARCH" != "arm64" ]] && ABI_DIR="$STAGE/lib/x86_64"
  cp "$ABI_DIR/libbusybox.so"     "$FLAT/busybox"
  cp "$ABI_DIR/libmagiskboot.so"  "$FLAT/magiskboot"
  cp "$ABI_DIR/libmagiskinit.so"  "$FLAT/magiskinit"
  cp "$ABI_DIR/libmagiskpolicy.so" "$FLAT/magiskpolicy"
  cp "$ABI_DIR/libmagisk64.so"    "$FLAT/magisk64"
  adb -s "$ADB_SERIAL" push "$FLAT/." /data/local/tmp/magisk-stage/ >/dev/null
  adb -s "$ADB_SERIAL" shell 'su -c "
    cp -r /data/local/tmp/magisk-stage/* /data/adb/magisk/
    chmod 755 /data/adb/magisk/busybox /data/adb/magisk/magisk*
    chmod 644 /data/adb/magisk/*.sh
  "'
  echo "  seeded support files into /data/adb/magisk/"
else
  echo "  already populated."
fi

# ---- 4. Reinstall the FULL Magisk app over rootAVD's stub ----
echo
echo "==> install full Magisk app"
FULL_APK="$ROOTAVD_DIR/Apps/Magisk.apk"
adb -s "$ADB_SERIAL" install -r "$FULL_APK" >/dev/null

# ---- 5. Install LSPosed zygisk module via module_installer.sh ----
# `magisk --install-module` returns 127 when called through `su -c` on AVD,
# but invoking module_installer.sh directly works reliably.
echo
echo "==> install LSPosed zygisk module"
adb -s "$ADB_SERIAL" push "$LS_ZIP" /data/local/tmp/lsposed.zip >/dev/null
adb -s "$ADB_SERIAL" shell 'su -c "
  sh /data/adb/magisk/module_installer.sh dummy 1 /data/local/tmp/lsposed.zip
" > /data/local/tmp/lsposed-install.log 2>&1'
if ! adb -s "$ADB_SERIAL" shell '[ -d /data/adb/modules_update/zygisk_lsposed ] || [ -d /data/adb/modules/zygisk_lsposed ]'; then
  echo "LSPosed install failed. Tail of install log:"
  adb -s "$ADB_SERIAL" shell 'tail -40 /data/local/tmp/lsposed-install.log'
  exit 1
fi

# ---- 6. LSPosed Manager (bundled inside the module, extracted by installer) ----
echo
echo "==> install LSPosed Manager"
adb -s "$ADB_SERIAL" shell 'su -c "cp /data/adb/modules_update/zygisk_lsposed/manager.apk /data/local/tmp/manager.apk 2>/dev/null \
  || cp /data/adb/modules/zygisk_lsposed/manager.apk /data/local/tmp/manager.apk"'
adb -s "$ADB_SERIAL" shell pm install -r /data/local/tmp/manager.apk

# ---- 7. Build the stealth module ----
echo
echo "==> build stealth module"
if [[ ! -f "$ROOT/mock-location-helper/local.properties" ]]; then
  echo "sdk.dir=$SDK" > "$ROOT/mock-location-helper/local.properties"
fi
if [[ -x "$ROOT/mock-location-helper/gradlew" ]]; then
  (cd "$ROOT/mock-location-helper" && ANDROID_HOME="$SDK" ./gradlew assembleDebug)
else
  (cd "$ROOT/mock-location-helper" && ANDROID_HOME="$SDK" gradle assembleDebug)
fi
STEALTH_APK="$ROOT/mock-location-helper/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$STEALTH_APK" ]] || { echo "stealth APK not produced at $STEALTH_APK"; exit 1; }

# ---- 8. Reboot FIRST so LSPosed daemon comes up, then install stealth APK
#       afterwards. If we install before reboot, the LSPosed daemon's first
#       package scan (during early boot) can miss our module and never re-scan.
echo
echo "==> reboot so LSPosed daemon comes up clean"
adb -s "$ADB_SERIAL" reboot
for i in $(seq 1 120); do
  if [[ "$(adb -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 1
done
adb -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
sleep 3
adb -s "$ADB_SERIAL" wait-for-device

echo
echo "==> install stealth APK (fires PACKAGE_ADDED so LSPosed registers it)"
adb -s "$ADB_SERIAL" install -r "$STEALTH_APK"

# Daemon registers PACKAGE_ADDED into the modules table asynchronously — give
# it a moment, then poll.
echo
echo "==> wait for LSPosed daemon to register the module"
REGISTERED=0
for i in $(seq 1 30); do
  if adb -s "$ADB_SERIAL" shell 'su -c "sqlite3 /data/adb/lspd/config/modules_config.db \"SELECT mid FROM modules WHERE module_pkg_name = '\''com.headless.mockloc'\'';\""' 2>/dev/null | grep -qE '^[0-9]'; then
    REGISTERED=1
    echo "  registered after ${i}s."
    break
  fi
  sleep 1
done
if [[ $REGISTERED -eq 0 ]]; then
  echo "  module not registered — check /data/adb/lspd/log/verbose_*.log for 'skipping'."
  echo "  current modules table:"
  adb -s "$ADB_SERIAL" shell 'su -c "sqlite3 -header -column /data/adb/lspd/config/modules_config.db \"SELECT * FROM modules;\""'
  exit 1
fi

# ---- 9. Enable the module + persist it via the DB ---------------------------
# LSPosed v1.11's parasitic-manager UI tab tends to render blank, so we bypass
# it: set enabled=1 directly. The daemon reads this on its next boot.
echo
echo "==> enable module in LSPosed DB"
adb -s "$ADB_SERIAL" shell 'su -c "sqlite3 /data/adb/lspd/config/modules_config.db \"UPDATE modules SET enabled = 1 WHERE module_pkg_name = '\''com.headless.mockloc'\'';\""'

# ---- 10. Second reboot — daemon now picks up enabled=1 and loads the module
#         into Zygote so scoped apps get the hooks.
echo
echo "==> reboot so the enabled module is loaded by Zygote"
adb -s "$ADB_SERIAL" reboot
for i in $(seq 1 120); do
  if [[ "$(adb -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 1
done
adb -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
sleep 2
adb -s "$ADB_SERIAL" wait-for-device

# Appop is per-uid runtime state; resets across reboot. Set it now (post-reboot).
echo
echo "==> grant android:mock_location appop (post-reboot)"
adb -s "$ADB_SERIAL" shell cmd appops set com.headless.mockloc android:mock_location allow

# ---- 11. Final verification ------------------------------------------------
echo
echo "==> verify daemon actually loaded our class"
LOG_LINE="$(adb -s "$ADB_SERIAL" shell 'su -c "grep -h \"Loading.*com.headless.mockloc\\|Loading class com.headless.mockloc\" /data/adb/lspd/log/verbose_*.log 2>/dev/null | tail -2"' 2>/dev/null)"
if [[ -n "$LOG_LINE" ]]; then
  echo "  loaded:"
  echo "$LOG_LINE" | sed 's/^/    /'
else
  echo "  WARNING: no 'Loading legacy module com.headless.mockloc' line in the verbose log."
  echo "  The module may not be loading into Zygote yet. Inspect:"
  echo "    adb shell 'su -c \"tail -40 /data/adb/lspd/log/verbose_*.log\"'"
fi

echo
echo "==> done."
echo
echo "Module is registered AND enabled. To actually have apps fooled by it,"
echo "scope-enable on each target app:"
echo
echo "  scripts/scope.sh add <com.your.target.app>"
echo "  scripts/scope.sh apply        # reboot so hook loads into the app"
echo
echo "List current scope:        scripts/scope.sh list"
echo "Remove a package:          scripts/scope.sh remove <package>"
