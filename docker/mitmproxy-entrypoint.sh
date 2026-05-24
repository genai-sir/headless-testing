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
  log "docker bridge for '${REDROID_NETWORK}' = ${BRIDGE}"

  log "configuring iptables PREROUTING REDIRECT on ${BRIDGE}"
  # Wipe any previous tap rules so re-runs are idempotent.
  iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true
  iptables -t nat -D PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true

  iptables -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 80  -j REDIRECT --to-ports ${LISTEN_PORT}
  iptables -t nat -A PREROUTING -i "${BRIDGE}" -p tcp --dport 443 -j REDIRECT --to-ports ${LISTEN_PORT}

  # REDIRECT to a local port means the host kernel needs to *accept*
  # packets destined to a non-local IP. By default `route_localnet=0` on
  # bridge interfaces blocks this — even though we share host netns, the
  # sysctl can be ro from inside the container, so try and warn-only.
  # If this warns, run on the host:
  #   sudo sysctl -w net.ipv4.conf.all.route_localnet=1
  #   sudo sysctl -w net.ipv4.conf.${BRIDGE}.route_localnet=1
  for path in \
    "/proc/sys/net/ipv4/conf/all/route_localnet" \
    "/proc/sys/net/ipv4/conf/${BRIDGE}/route_localnet" \
    "/proc/sys/net/ipv4/conf/all/accept_local" \
    "/proc/sys/net/ipv4/conf/${BRIDGE}/accept_local"; do
    [ -w "$path" ] && echo 1 > "$path" 2>/dev/null
  done
  if [ "$(cat /proc/sys/net/ipv4/conf/${BRIDGE}/route_localnet 2>/dev/null)" != "1" ]; then
    log "  WARN: route_localnet=0 on ${BRIDGE}; run on host:"
    log "    sudo sysctl -w net.ipv4.conf.${BRIDGE}.route_localnet=1"
    log "    sudo sysctl -w net.ipv4.conf.all.route_localnet=1"
  fi

  log "iptables rules installed:"
  iptables -t nat -S PREROUTING | grep -F "${BRIDGE}" | sed 's/^/    /'
fi

# Make sure config dir is writable by 8181 (volume might be fresh).
chown -R ${MITM_UID}:${MITM_UID} "${CONFDIR}"

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
