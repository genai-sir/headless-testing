#!/usr/bin/env bash
# Entrypoint for the host-bridge transparent mitmproxy tap.
#
# Runtime layout: this container runs with `network_mode: host`, so it shares
# the host's network namespace. Redroid is on the docker_hl bridge — its
# outbound packets traverse that bridge interface in the host kernel. We
# install iptables PREROUTING rules on that bridge interface to REDIRECT
# TCP 80/443 to mitmproxy's transparent listener (127.0.0.1:8080), all in
# the host netns where SO_ORIGINAL_DST is preserved by the conntrack record.
#
# This sidesteps Android's `netd`/fwmark routing that ate the rules when
# mitmproxy was inside redroid's netns.
#
# Listening ports on the host (network_mode: host):
#   8080  transparent proxy   (target of the iptables REDIRECT)
#   8081  mitmweb UI + API    (browser + dashboard hit this)
#   9050  SOCKS5              (reserved for future PCAPdroid-style chaining)

set -euo pipefail

MITM_UID=8181
LISTEN_PORT=8080
SOCKS_PORT=9050
WEB_PORT=8081
CONFDIR=/home/mitmproxy/.mitmproxy
WEB_PASSWORD="${MITM_WEB_PASSWORD:-headless-mitm}"
REDROID_NETWORK="${REDROID_NETWORK:-docker_hl}"

log() { printf "\033[36m[mitm-tap]\033[0m %s\n" "$*"; }

# Resolve the docker bridge interface that carries the docker_hl network.
# Docker names bridges `br-<12-hex>`. We find it by looking for a bridge
# whose name matches the network's docker-network-id prefix. If multiple
# match (shouldn't), pick the first.
resolve_bridge() {
  # Strategy: every docker network with the bridge driver gets a Linux
  # bridge interface. The interface name is `br-<first 12 chars of id>`.
  # We don't have the docker CLI in this container, but `/sys/class/net`
  # lists all bridges visible in the host netns we joined.
  for ifc in /sys/class/net/br-*; do
    [ -e "$ifc" ] || continue
    local name; name="$(basename "$ifc")"
    # Match by the network name baked into ip address scope: docker writes
    # `bridge.name=docker_hl` into the bridge's link metadata, accessible
    # via `ip -d link show`. Probe each candidate.
    if ip -d link show dev "$name" 2>/dev/null | grep -q "${REDROID_NETWORK}"; then
      echo "$name"
      return 0
    fi
  done
  # Fallback heuristic: if there's exactly one br-* bridge, use it.
  local all=(); for ifc in /sys/class/net/br-*; do
    [ -e "$ifc" ] && all+=("$(basename "$ifc")")
  done
  if [ "${#all[@]}" -eq 1 ]; then
    echo "${all[0]}"
    return 0
  fi
  return 1
}

BRIDGE="$(resolve_bridge || true)"
if [ -z "$BRIDGE" ]; then
  log "WARNING: could not resolve bridge for network '${REDROID_NETWORK}'."
  log "  Available br-* interfaces:"
  ls /sys/class/net/ 2>/dev/null | grep ^br- | sed 's/^/    /' || echo "    (none)"
  log "  Set REDROID_NETWORK in .env to match the docker network containing redroid."
  log "  Continuing without the iptables tap — mitmweb will start but won't capture anything."
else
  # The bridge gateway IP is the host side of the docker bridge — that is,
  # the local IP we DNAT to. Always the first usable address of the docker
  # network's subnet (172.X.0.1 by default).
  GATEWAY="$(ip -4 -o addr show dev "${BRIDGE}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
  log "docker bridge for '${REDROID_NETWORK}' = ${BRIDGE} (gateway ${GATEWAY:-?})"

  if [ -z "$GATEWAY" ]; then
    log "  ERROR: bridge ${BRIDGE} has no IPv4 address; can't DNAT to it."
  else
    # DNAT to the bridge gateway IP rather than REDIRECT to localhost. Both
    # are functionally equivalent (mitmproxy reads SO_ORIGINAL_DST from
    # conntrack either way) but REDIRECT to 127.0.0.1 makes the host kernel
    # treat the post-NAT packet as a martian — source 172.18.x is not
    # loopback, destination is — and silently drop it even with
    # route_localnet=1. DNAT to the bridge's own IP keeps source and
    # destination plausibly routable so the packet lands in mitmproxy's
    # listening socket.
    log "configuring iptables PREROUTING DNAT on ${BRIDGE} -> ${GATEWAY}:${LISTEN_PORT}"
    # Wipe any previous tap rules so re-runs are idempotent. Cover both
    # REDIRECT and DNAT forms from earlier iterations.
    iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}" 2>/dev/null || true

    iptables -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}"
    iptables -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j DNAT --to-destination "${GATEWAY}:${LISTEN_PORT}"

    log "iptables rules installed:"
    iptables -t nat -S PREROUTING | grep -F "${BRIDGE}" | sed 's/^/    /'
  fi
fi

# Make sure config dir is writable by 8181 (volume might be fresh).
chown -R ${MITM_UID}:${MITM_UID} "${CONFDIR}"

# Start the tiny control server as root, in background. It listens on
# port 8082 for /enable, /disable, /status and toggles the iptables DNAT
# rules. Lives in the same container so it inherits CAP_NET_ADMIN and the
# host network namespace. Backend reaches it via host.docker.internal:8082.
log "starting control server on :8082 (root, NET_ADMIN)"
MITM_WEB_PASSWORD="${WEB_PASSWORD}" \
LISTEN_PORT="${LISTEN_PORT}" \
REDROID_NETWORK="${REDROID_NETWORK}" \
  /control.py &

log "starting mitmweb (transparent on ${LISTEN_PORT}, socks5 on ${SOCKS_PORT}, ui on ${WEB_PORT})"
exec gosu ${MITM_UID}:${MITM_UID} \
  mitmweb \
    --mode "transparent@${LISTEN_PORT}" \
    --mode "socks5@${SOCKS_PORT}" \
    --listen-host 0.0.0.0 \
    --web-host 0.0.0.0 \
    --web-port ${WEB_PORT} \
    --no-web-open-browser \
    --showhost \
    --set "confdir=${CONFDIR}" \
    --set "web_password=${WEB_PASSWORD}" \
    --set web_open_browser=false \
    --set block_global=false \
    --set ssl_insecure=true \
    --set flow_detail=2
