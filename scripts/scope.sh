#!/usr/bin/env bash
# Manage which apps the headless-android stealth module hooks into.
#
# Bypasses the LSPosed Manager UI by writing directly to
# /data/adb/lspd/config/modules_config.db.
#
# Usage:
#   scripts/scope.sh add <package>     # scope-enable on a package
#   scripts/scope.sh remove <package>   # scope-disable
#   scripts/scope.sh list               # show current scope rows
#   scripts/scope.sh apply              # reboot so the daemon re-reads scope
#
# Scope changes only take effect after the target app's process is
# (re)spawned from Zygote. The most reliable way is `apply` (reboot);
# `force-stop <pkg> && am start` is sometimes enough for one app.
set -euo pipefail

MOD_PKG="${MOD_PKG:-com.headless.mockloc}"
USER_ID="${USER_ID:-0}"
DB="/data/adb/lspd/config/modules_config.db"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="${ADB:-$SDK/platform-tools/adb}"
ADB_SERIAL="${ADB_SERIAL:-emulator-5554}"

sql() {
  "$ADB" -s "$ADB_SERIAL" shell "su -c \"sqlite3 $DB \\\"$1\\\"\""
}

cmd_add() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo "usage: scope.sh add <package>" >&2; exit 1
  fi
  local mid
  mid="$(sql "SELECT mid FROM modules WHERE module_pkg_name='${MOD_PKG}';" | tr -d '\r' || true)"
  if [[ -z "$mid" ]]; then
    echo "module '${MOD_PKG}' not registered in LSPosed. Run scripts/install-magisk-avd.sh first." >&2
    exit 1
  fi
  sql "INSERT OR IGNORE INTO scope (mid, app_pkg_name, user_id) VALUES (${mid}, '${target}', ${USER_ID});" >/dev/null
  echo "added '${target}' to scope (mid=${mid}). Run 'scripts/scope.sh apply' for it to take effect."
}

cmd_remove() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo "usage: scope.sh remove <package>" >&2; exit 1
  fi
  sql "DELETE FROM scope WHERE app_pkg_name='${target}' AND user_id=${USER_ID};" >/dev/null
  echo "removed '${target}'. Run 'scripts/scope.sh apply' for it to take effect."
}

cmd_list() {
  echo "=== modules ==="
  "$ADB" -s "$ADB_SERIAL" shell "su -c \"sqlite3 -header -column $DB 'SELECT mid, module_pkg_name, enabled FROM modules;'\""
  echo
  echo "=== scope ==="
  "$ADB" -s "$ADB_SERIAL" shell "su -c \"sqlite3 -header -column $DB 'SELECT * FROM scope;'\""
}

cmd_apply() {
  echo "rebooting…"
  "$ADB" -s "$ADB_SERIAL" reboot
  for i in $(seq 1 120); do
    if [[ "$("$ADB" -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      echo "  back online after ${i}s"
      break
    fi
    sleep 1
  done
  "$ADB" -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
  sleep 2
  "$ADB" -s "$ADB_SERIAL" shell cmd appops set "$MOD_PKG" android:mock_location allow
  echo "  ready."
}

case "${1:-}" in
  add)    cmd_add "${2:-}" ;;
  remove) cmd_remove "${2:-}" ;;
  list)   cmd_list ;;
  apply)  cmd_apply ;;
  *)      cat <<EOF >&2
usage:
  $(basename "$0") add <package>      scope-enable on a package
  $(basename "$0") remove <package>   scope-disable
  $(basename "$0") list               show modules + scope tables
  $(basename "$0") apply              reboot so changes take effect

env:
  MOD_PKG    LSPosed module package (default: com.headless.mockloc)
  USER_ID    Android user id        (default: 0)
  ADB_SERIAL adb -s target          (default: emulator-5554)
EOF
          exit 2 ;;
esac
