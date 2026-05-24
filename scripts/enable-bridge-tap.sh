#!/usr/bin/env bash
# Validate the host environment for the bridge-mode mitmproxy tap.
#
# After moving from REDIRECT-to-localhost to DNAT-to-bridge-gateway, the
# host sysctls (route_localnet, accept_local) aren't required anymore —
# DNAT to the bridge's own IP keeps the packet's destination plausibly
# routable, so the kernel doesn't drop it as a martian. This script is
# now just a diagnostic helper that prints whether the stack is set up
# correctly, and what the docker bridge / gateway IP are so you can
# eyeball the mitmproxy entrypoint output against reality.
#
# Usage:
#   scripts/enable-bridge-tap.sh           # diagnostic only
#   scripts/enable-bridge-tap.sh --apply   # also write iptables rules now
#
# Normally the mitmproxy container's entrypoint installs the iptables
# rules itself on start. Use --apply when debugging or when you want the
# capture active without the container running.

set -euo pipefail

REDROID_NETWORK="${REDROID_NETWORK:-docker_hl}"
LISTEN_PORT="${LISTEN_PORT:-8080}"
DO_APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) DO_APPLY=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

say() { printf "\033[32m==>\033[0m %s\n" "$*"; }
die() { printf "\033[31merror:\033[0m %s\n" "$*" >&2; exit 1; }
warn() { printf "\033[33mwarn:\033[0m %s\n" "$*" >&2; }

command -v docker >/dev/null || die "docker not on PATH"
command -v ip >/dev/null || die "iproute2 not on PATH"

say "docker network -> bridge"
BRIDGE_ID="$(docker network inspect "${REDROID_NETWORK}" --format '{{.Id}}' 2>/dev/null | cut -c1-12)"
[ -n "$BRIDGE_ID" ] || die "docker network '${REDROID_NETWORK}' not found — bring the stack up first"
BRIDGE="br-${BRIDGE_ID}"
ip link show "${BRIDGE}" >/dev/null 2>&1 || die "bridge ${BRIDGE} does not exist"
GATEWAY="$(ip -4 -o addr show dev "${BRIDGE}" | awk '{print $4}' | cut -d/ -f1 | head -1)"
echo "    network=${REDROID_NETWORK}  bridge=${BRIDGE}  gateway=${GATEWAY}"

say "mitmproxy listener (expecting host port ${LISTEN_PORT})"
if ss -tlnp 2>/dev/null | grep -q ":${LISTEN_PORT} .*mitmweb"; then
  echo "    mitmweb listening on ${LISTEN_PORT} ✓"
else
  warn "no mitmweb listener on :${LISTEN_PORT} — capture won't work until the mitmproxy container is up"
fi

say "iptables (nft) PREROUTING rule for ${BRIDGE}"
if iptables-nft -t nat -S PREROUTING 2>/dev/null | grep -q "${BRIDGE}.*dport 443.*DNAT"; then
  echo "    DNAT rule present ✓"
  iptables-nft -t nat -S PREROUTING | grep -F "${BRIDGE}" | sed 's/^/    /'
elif iptables-nft -t nat -S PREROUTING 2>/dev/null | grep -q "${BRIDGE}.*REDIRECT"; then
  warn "older REDIRECT rule present — the entrypoint should replace it on next mitmproxy restart"
  iptables-nft -t nat -S PREROUTING | grep -F "${BRIDGE}" | sed 's/^/    /'
else
  warn "no PREROUTING rule for ${BRIDGE} — start (or restart) the mitmproxy container"
fi

if [ "$DO_APPLY" -eq 1 ]; then
  say "applying iptables rule now (--apply)"
  [ "$(id -u)" -eq 0 ] || die "--apply requires root (use sudo)"
  iptables-nft -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}" 2>/dev/null || true
  iptables-nft -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}" 2>/dev/null || true
  iptables-nft -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}"
  iptables-nft -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}"
  echo "    rules added."
fi

say "done."
