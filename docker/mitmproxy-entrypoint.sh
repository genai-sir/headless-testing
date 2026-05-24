#!/usr/bin/env bash
# Entrypoint for the transparent mitmproxy tap.
#
# Runtime layout: this container shares the network namespace of the redroid
# container (see compose `network_mode: service:redroid`). So:
#   - iptables OUTPUT in this namespace catches traffic emitted by Android apps
#     running inside redroid (which uses the same netns).
#   - mitmproxy listens on 0.0.0.0:8080 of that same netns; the OS-level
#     REDIRECT preserves SO_ORIGINAL_DST so transparent mode can recover the
#     intended destination host.
#   - mitmweb's UI listens on 8081 of that same netns; redroid's docker port
#     mapping (8081:8081 in the compose file) exposes it to the host.
#
# We skip-redirect traffic originating from uid 8181 (mitmproxy itself); without
# this filter we'd recursively REDIRECT mitmproxy's upstream connection back
# into itself and the proxy would deadlock.

set -euo pipefail

MITM_UID=8181
LISTEN_PORT=8080
WEB_PORT=8081
CONFDIR=/home/mitmproxy/.mitmproxy
WEB_PASSWORD="${MITM_WEB_PASSWORD:-headless-mitm}"

log() { printf "\033[36m[mitm-tap]\033[0m %s\n" "$*"; }

log "configuring iptables REDIRECT for ports 80/443"
# Wipe any previous tap rules (idempotent reload).
iptables -t nat -F OUTPUT 2>/dev/null || true

iptables -t nat -A OUTPUT -p tcp --dport 80 \
  -m owner ! --uid-owner ${MITM_UID} \
  -j REDIRECT --to-ports ${LISTEN_PORT}

iptables -t nat -A OUTPUT -p tcp --dport 443 \
  -m owner ! --uid-owner ${MITM_UID} \
  -j REDIRECT --to-ports ${LISTEN_PORT}

# Chrome and other modern clients prefer QUIC (HTTP/3) over UDP 443 by default.
# QUIC bypasses any TCP-only interception. Drop UDP 443 (and the QUIC default
# 80) so clients negotiate fallback to TCP+TLS, which our REDIRECT then
# catches. iptable_filter is required for this to load — but on the rare host
# where it isn't loaded, the line is a no-op so we don't fail the entrypoint.
iptables -A OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null \
  || log "  (udp 443 reject not installed — iptable_filter missing on host; QUIC may leak)"

log "iptables rules installed:"
iptables -t nat -S OUTPUT | sed 's/^/    /' || true

# Make sure config dir is writable by 8181 (volume might be fresh).
chown -R ${MITM_UID}:${MITM_UID} "${CONFDIR}"

log "starting mitmweb in transparent mode (uid ${MITM_UID})"
exec gosu ${MITM_UID}:${MITM_UID} \
  mitmweb \
    --mode transparent \
    --listen-host 0.0.0.0 \
    --listen-port ${LISTEN_PORT} \
    --web-host 0.0.0.0 \
    --web-port ${WEB_PORT} \
    --no-web-open-browser \
    --showhost \
    --set "confdir=${CONFDIR}" \
    --set "web_password=${WEB_PASSWORD}" \
    --set web_open_browser=false \
    --set block_global=false \
    --set ssl_insecure=true \
    --set termlog_verbosity=debug \
    --set flow_detail=2
