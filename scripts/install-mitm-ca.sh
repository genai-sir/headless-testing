#!/usr/bin/env bash
# Install the mitmproxy CA into redroid as a *system* CA so apps trust HTTPS
# flowing through the proxy without per-app cert errors.
#
# Why a Magisk module and not /system/etc/security/cacerts/ directly:
#   redroid's /system is squashfs-immutable. Magisk overlays a writable layer
#   via its module system. Dropping the cert in
#     <module>/system/etc/security/cacerts/<hash>.0
#   makes the system trust store include it after reboot — survives container
#   restarts as long as redroid-data persists.
#
# Usage:
#   sudo scripts/install-mitm-ca.sh
#
# Requirements:
#   - the `mitmproxy` container is running (its CA lives in the mitmproxy-data volume)
#   - redroid is up, adb reachable at 127.0.0.1:5555, Magisk installed
#   - openssl on the host
set -euo pipefail

ADB_SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
MITM_CONTAINER="${MITM_CONTAINER:-headless-mitmproxy}"
MODULE_ID="mitmproxy-ca"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf "\033[32m==>\033[0m %s\n" "$*"; }
die() { printf "\033[31merror:\033[0m %s\n" "$*" >&2; exit 1; }

command -v openssl >/dev/null || die "openssl not found on host"
docker inspect "$MITM_CONTAINER" >/dev/null 2>&1 || die "container '$MITM_CONTAINER' not running"

say "pull CA from mitmproxy container"
# mitmweb writes the CA on first start. If we get here before that, retry.
for i in $(seq 1 30); do
  if docker exec "$MITM_CONTAINER" test -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.cer 2>/dev/null; then
    docker cp "$MITM_CONTAINER":/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.cer "$WORK/ca.pem"
    break
  fi
  [ "$i" -eq 30 ] && die "mitmproxy CA file never appeared; is the proxy fully started?"
  sleep 1
done

say "compute Android-compatible cert hash"
# Android's CA store keys certs by the OpenSSL "subject_hash_old" (8 hex chars).
HASH="$(openssl x509 -in "$WORK/ca.pem" -inform PEM -subject_hash_old -noout)"
[ -n "$HASH" ] || die "could not compute cert hash"
echo "    hash=$HASH"

say "build Magisk module skeleton"
MODDIR="$WORK/mod"
mkdir -p "$MODDIR/system/etc/security/cacerts"
cp "$WORK/ca.pem" "$MODDIR/system/etc/security/cacerts/${HASH}.0"
chmod 644 "$MODDIR/system/etc/security/cacerts/${HASH}.0"

cat > "$MODDIR/module.prop" <<EOF
id=${MODULE_ID}
name=mitmproxy CA
version=1.0
versionCode=1
author=headless-android
description=Adds the mitmproxy CA to the system trust store so HTTPS traffic from redroid apps can be decrypted by the local proxy.
EOF

# Magisk module installer expects a zip with a META-INF/com/google/android
# update-binary, OR you can install directly by pushing the directory tree to
# /data/adb/modules_update/<id>/ and rebooting. The directory approach is what
# `magisk --install-module` ultimately does and is simpler from a script.
say "ensure adbd is running as root (needed to write under /data/adb)"
adb -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
sleep 1
adb -s "$ADB_SERIAL" wait-for-device

say "pre-authorize ADB shell in Magisk's su policy (uid 2000 -> ALLOW)"
# Without this, /sbin/su -c '...' would ASK on the device UI and fail silently.
# Default Magisk policy table: policy 2 = ALLOW, 1 = DENY, 0 = ASK.
# We need until=0 so it's permanent, log=0 to keep the log clean.
adb -s "$ADB_SERIAL" shell '
  if [ -e /data/adb/magisk.db ]; then
    /system/bin/sqlite3 /data/adb/magisk.db \
      "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (2000,2,0,0,0);" 2>/dev/null || true
  fi
'

say "stage module on redroid"
adb -s "$ADB_SERIAL" shell 'rm -rf /data/local/tmp/'"$MODULE_ID"
adb -s "$ADB_SERIAL" push "$MODDIR" "/data/local/tmp/${MODULE_ID}" >/dev/null

say "promote into Magisk modules tree"
# /data/adb/modules_update is a staging dir Magisk creates on first use;
# mkdir -p covers fresh installs. With adbd running as root we can write
# directly; if not we fall back through /sbin/su.
INSTALL_SCRIPT="
  set -e
  mkdir -p /data/adb/modules_update /data/adb/modules
  rm -rf /data/adb/modules_update/${MODULE_ID}
  cp -a /data/local/tmp/${MODULE_ID} /data/adb/modules_update/${MODULE_ID}
  touch /data/adb/modules_update/${MODULE_ID}/update
  rm -rf /data/adb/modules/${MODULE_ID}
  cp -a /data/adb/modules_update/${MODULE_ID} /data/adb/modules/${MODULE_ID}
"
if ! adb -s "$ADB_SERIAL" shell "$INSTALL_SCRIPT"; then
  say "  direct write failed, falling back to /sbin/su"
  adb -s "$ADB_SERIAL" shell "/sbin/su -c '${INSTALL_SCRIPT}'"
fi

say "reboot redroid so the overlay mounts the new cert"
adb -s "$ADB_SERIAL" reboot
until [ "$(adb -s "$ADB_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  printf .
  sleep 3
done
echo " booted"
adb -s "$ADB_SERIAL" root >/dev/null 2>&1 || true
sleep 3
adb -s "$ADB_SERIAL" connect "$ADB_SERIAL" >/dev/null 2>&1 || true

say "verify cert is in system trust store"
if adb -s "$ADB_SERIAL" shell "/sbin/su -c 'ls /system/etc/security/cacerts/${HASH}.0'" >/dev/null 2>&1; then
  echo "    /system/etc/security/cacerts/${HASH}.0 present"
else
  die "cert not visible in /system/etc/security/cacerts/ after reboot; check 'magisk --list' inside redroid"
fi

say "done. Now point redroid at the proxy:"
echo "    adb -s $ADB_SERIAL shell settings put global http_proxy mitmproxy:8080"
echo "  or use the dashboard 'Traffic' panel toggle."
