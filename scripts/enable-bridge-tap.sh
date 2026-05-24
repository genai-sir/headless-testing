#!/usr/bin/env bash
# One-shot host setup for the bridge-mode mitmproxy tap.
#
# The mitmproxy entrypoint installs the iptables PREROUTING REDIRECT rules
# itself, but two sysctls (route_localnet, accept_local) are sometimes
# read-only from inside the container even when sharing the host netns. We
# flip them here from the host.
#
# Also makes the values persist across reboots via /etc/sysctl.d/.
#
# Usage:
#   sudo scripts/enable-bridge-tap.sh
#
# Idempotent — safe to run repeatedly.

set -euo pipefail

REDROID_NETWORK="${REDROID_NETWORK:-docker_hl}"

say() { printf "\033[32m==>\033[0m %s\n" "$*"; }
die() { printf "\033[31merror:\033[0m %s\n" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"

say "find docker bridge for network '${REDROID_NETWORK}'"
BRIDGE_ID="$(docker network inspect "${REDROID_NETWORK}" --format '{{.Id}}' 2>/dev/null | cut -c1-12)"
[ -n "$BRIDGE_ID" ] || die "docker network '${REDROID_NETWORK}' not found; bring the stack up first"
BRIDGE="br-${BRIDGE_ID}"
ip link show "${BRIDGE}" >/dev/null 2>&1 || die "bridge interface ${BRIDGE} does not exist"
echo "    ${BRIDGE}"

say "set sysctls for transparent proxy delivery"
# - route_localnet allows the kernel to deliver post-REDIRECT packets
#   (whose destination has been rewritten to 127.0.0.1:8080) to the local
#   stack instead of dropping them as martians.
# - accept_local lets packets with a non-loopback source reach a loopback
#   destination through this interface.
sysctl -w "net.ipv4.conf.${BRIDGE}.route_localnet=1"
sysctl -w "net.ipv4.conf.${BRIDGE}.accept_local=1"
sysctl -w "net.ipv4.conf.all.route_localnet=1"

say "persist across reboot"
# Note: bridge interface name (br-XXXXX) is derived from the docker
# network ID and is stable across recreates as long as the network
# exists. If you `docker network rm` and recreate, the name changes
# and this file becomes stale — re-run this script.
cat > /etc/sysctl.d/99-headless-android-bridge-tap.conf <<EOF
# Managed by scripts/enable-bridge-tap.sh — do not edit directly.
net.ipv4.conf.${BRIDGE}.route_localnet = 1
net.ipv4.conf.${BRIDGE}.accept_local   = 1
net.ipv4.conf.all.route_localnet       = 1
EOF
echo "    /etc/sysctl.d/99-headless-android-bridge-tap.conf"

say "done. now (re)start the mitmproxy container so its entrypoint re-installs the iptables rules."
echo
echo "  cd docker && docker compose up -d --force-recreate mitmproxy"
