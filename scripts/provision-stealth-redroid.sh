#!/usr/bin/env bash
# Provision the stealth stack inside a fresh redroid container.
#
# Assumes:
#   - Container is running with a Magisk-baked image (see build-redroid-image.sh)
#   - adb on the host can reach it (default: 127.0.0.1:5555)
#   - Network access to GitHub for fetching LSPosed and the Magisk module APK
#
# Idempotent: safe to re-run. Skips steps whose result is already present.
#
# Usage:
#   sudo scripts/provision-stealth-redroid.sh                # default everything
#   sudo ADB_SERIAL=127.0.0.1:5555 scripts/provision-stealth-redroid.sh
#   sudo SCOPE_PKGS="com.example.a com.example.b" scripts/provision-stealth-redroid.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB_SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
ADB="adb -s $ADB_SERIAL"

STEALTH_APK="${STEALTH_APK:-$ROOT/mock-location-helper/app/build/outputs/apk/debug/app-debug.apk}"
LSPOSED_ZIP="${LSPOSED_ZIP:-}"
SCOPE_PKGS="${SCOPE_PKGS:-}"
STEALTH_PKG="com.headless.mockloc"

require() { command -v "$1" >/dev/null || { echo "missing $1" >&2; exit 1; }; }
require adb
require curl
require unzip

# --- 1. wait for boot ---------------------------------------------------------
echo "==> waiting for $ADB_SERIAL to boot"
$ADB connect "$ADB_SERIAL" >/dev/null 2>&1 || true
until [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  echo -n "."; sleep 3
done
echo " booted"
$ADB root >/dev/null 2>&1 || true
sleep 2
$ADB connect "$ADB_SERIAL" >/dev/null 2>&1 || true

# --- 2. verify Magisk daemon is up -------------------------------------------
MAGISK_V="$($ADB shell '/sbin/su -v' 2>/dev/null | tr -d '\r')"
[ -n "$MAGISK_V" ] || { echo "Magisk not detected. Did you use a Magisk-baked image?" >&2; exit 1; }
echo "==> Magisk: $MAGISK_V"

# --- 3. seed /data/adb/magisk if empty ---------------------------------------
echo "==> seed /data/adb/magisk"
if $ADB shell '/sbin/su -c "test -f /data/adb/magisk/util_functions.sh"' >/dev/null 2>&1; then
  echo "  already seeded."
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  $ADB pull /system/etc/init/magisk/magisk.apk "$TMP/magisk.apk" >/dev/null
  unzip -q "$TMP/magisk.apk" -d "$TMP/m" 'assets/*.sh'
  for s in util_functions.sh module_installer.sh boot_patch.sh addon.d.sh uninstaller.sh; do
    $ADB push "$TMP/m/assets/$s" "/data/local/tmp/$s" >/dev/null
  done
  $ADB shell '/sbin/su -c "
    cp /system/etc/init/magisk/busybox /data/adb/magisk/
    cp /system/etc/init/magisk/magiskboot /data/adb/magisk/
    cp /system/etc/init/magisk/magiskinit /data/adb/magisk/
    cp /system/etc/init/magisk/magiskpolicy /data/adb/magisk/
    cp /system/etc/init/magisk/magisk /data/adb/magisk/magisk64
    for s in util_functions.sh module_installer.sh boot_patch.sh addon.d.sh uninstaller.sh; do
      cp /data/local/tmp/$s /data/adb/magisk/
    done
    chmod 755 /data/adb/magisk/*
  "'
  echo "  seeded."
fi

# --- 4. enable Zygisk --------------------------------------------------------
echo "==> enable Zygisk"
$ADB shell '/sbin/magisk --sqlite "REPLACE INTO settings (key,value) VALUES(\"zygisk\",1);"' >/dev/null

# --- 5. install LSPosed-Zygisk if not present --------------------------------
echo "==> LSPosed module"
if $ADB shell '/sbin/su -c "test -d /data/adb/modules/zygisk_lsposed"' >/dev/null 2>&1; then
  echo "  already installed."
else
  if [ -z "$LSPOSED_ZIP" ]; then
    LSPOSED_ZIP="$(mktemp).zip"
    URL="$(curl -sfL 'https://api.github.com/repos/JingMatrix/LSPosed/releases?per_page=20' \
      | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    for a in r.get('assets', []):
        n = a.get('name', '')
        if n.startswith('LSPosed-') and n.endswith('-zygisk-release.zip'):
            print(a['browser_download_url']); sys.exit(0)
")"
    [ -n "$URL" ] || { echo "  could not resolve LSPosed release" >&2; exit 1; }
    echo "  fetching $URL"
    curl -sfL "$URL" -o "$LSPOSED_ZIP"
  fi
  $ADB push "$LSPOSED_ZIP" /data/local/tmp/lsposed.zip >/dev/null
  $ADB shell '/sbin/su -c "/sbin/magisk --install-module /data/local/tmp/lsposed.zip 2>&1 | tail -5"'
  $ADB shell '/sbin/su -c "test -d /data/adb/modules_update/zygisk_lsposed || test -d /data/adb/modules/zygisk_lsposed"' \
    || { echo "  LSPosed module install failed" >&2; exit 1; }
fi

# --- 6. install LSPosed Manager APK ------------------------------------------
echo "==> LSPosed Manager APK"
if $ADB shell pm list packages org.lsposed.manager 2>/dev/null | grep -q org.lsposed.manager; then
  echo "  already installed."
else
  $ADB shell '/sbin/su -c "
    cp /data/adb/modules_update/zygisk_lsposed/manager.apk /data/local/tmp/manager.apk 2>/dev/null \
      || cp /data/adb/modules/zygisk_lsposed/manager.apk /data/local/tmp/manager.apk
    chmod 644 /data/local/tmp/manager.apk
  "'
  $ADB shell pm install -r /data/local/tmp/manager.apk
fi

# --- 7. reboot if zygisk just enabled or LSPosed just installed --------------
NEEDS_REBOOT=0
$ADB shell pidof lspd >/dev/null 2>&1 || NEEDS_REBOOT=1
if [ "$NEEDS_REBOOT" -eq 1 ]; then
  echo "==> reboot for Zygisk/LSPosed to load"
  $ADB reboot
  until [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do echo -n "."; sleep 3; done
  echo " booted"
  $ADB root >/dev/null 2>&1 || true
  sleep 3
  $ADB connect "$ADB_SERIAL" >/dev/null 2>&1 || true
  sleep 2
fi

# --- 8. install stealth APK --------------------------------------------------
echo "==> stealth APK ($STEALTH_PKG)"
ALREADY_INSTALLED=0
$ADB shell pm list packages "$STEALTH_PKG" 2>/dev/null | grep -q "$STEALTH_PKG" && ALREADY_INSTALLED=1
if [ -f "$STEALTH_APK" ]; then
  $ADB install -r "$STEALTH_APK"
elif [ "$ALREADY_INSTALLED" -eq 1 ]; then
  echo "  no APK staged but $STEALTH_PKG already installed; keeping existing."
elif [ -d "$ROOT/mock-location-helper" ] && [ -x "$ROOT/mock-location-helper/gradlew" ]; then
  echo "  building (gradle assembleDebug)..."
  ( cd "$ROOT/mock-location-helper" && ./gradlew assembleDebug -q 2>&1 | tail -5 )
  $ADB install -r "$STEALTH_APK"
else
  echo "  stealth APK not staged and not buildable here." >&2
  echo "  pass STEALTH_APK=/path/to/app-debug.apk or run from a checkout with gradlew." >&2
  exit 1
fi

# --- 9. wait for LSPosed to register, then enable ----------------------------
echo "==> register + enable module in LSPosed DB"
MID=""
for i in $(seq 1 30); do
  MID="$($ADB shell "/sbin/su -c \"sqlite3 /data/adb/lspd/config/modules_config.db 'SELECT mid FROM modules WHERE module_pkg_name = \\\"$STEALTH_PKG\\\";'\"" 2>/dev/null | tr -d '\r')"
  [[ "$MID" =~ ^[0-9]+$ ]] && break
  sleep 1
done
[ -n "$MID" ] || { echo "  module not registered" >&2; exit 1; }
echo "  mid=$MID"
$ADB shell "/sbin/su -c \"sqlite3 /data/adb/lspd/config/modules_config.db 'UPDATE modules SET enabled=1 WHERE mid=$MID;'\""

# --- 10. apply scope ---------------------------------------------------------
if [ -n "$SCOPE_PKGS" ]; then
  echo "==> scope: $SCOPE_PKGS"
  for pkg in $SCOPE_PKGS; do
    $ADB shell "/sbin/su -c \"sqlite3 /data/adb/lspd/config/modules_config.db 'INSERT OR IGNORE INTO scope (mid, app_pkg_name, user_id) VALUES ($MID, \\\"$pkg\\\", 0);'\""
  done
fi

# --- 11. reboot so Zygote loads the module into scoped apps -----------------
echo "==> final reboot"
$ADB reboot
until [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do echo -n "."; sleep 3; done
echo " booted"
$ADB root >/dev/null 2>&1 || true
sleep 3
$ADB connect "$ADB_SERIAL" >/dev/null 2>&1 || true

# --- 12. grant mock_location appop (resets across reboot) -------------------
echo "==> grant android:mock_location appop"
$ADB shell cmd appops set "$STEALTH_PKG" android:mock_location allow
$ADB shell cmd appops get "$STEALTH_PKG" android:mock_location

echo
echo "==> done. verify: curl http://localhost:3000/api/stealth"
