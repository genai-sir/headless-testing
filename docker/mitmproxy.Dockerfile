# mitmproxy in transparent-tap mode for redroid.
#
# Why we extend the upstream image:
#   1. We need `iptables` so the entrypoint can install REDIRECT rules.
#   2. We need a known non-colliding uid for the `-m owner --uid-owner` filter
#      (Android assigns uid 1000 to system; the upstream image runs mitmproxy
#      as uid 1000 — so the default would either capture loop or skip system
#      traffic depending on order).
#
# The compose file places this container in redroid's network namespace
# (`network_mode: "service:redroid"`), so the iptables rules apply to traffic
# originating from inside redroid's Android. mitmproxy reads SO_ORIGINAL_DST
# (preserved by REDIRECT in the same kernel namespace) to learn the real host.

FROM mitmproxy/mitmproxy:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 gosu \
 && rm -rf /var/lib/apt/lists/* \
 # The host kernel typically loads the legacy xtables netfilter modules, not
 # the nft-backed ones. Default iptables on Debian 12 is nft; flip to legacy
 # so REDIRECT/owner extensions resolve.
 && update-alternatives --set iptables /usr/sbin/iptables-legacy \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
 # Dedicated uid so the iptables `--uid-owner` filter can spare mitmproxy's
 # own upstream connections without colliding with Android uids.
 && useradd -u 8181 -m -d /home/mitm-tap mitm-tap

# Persist the same /home/mitmproxy/.mitmproxy path the mitmweb tooling expects
# (CA cert location) but make it traversable by uid 8181. The upstream image
# ships /home/mitmproxy as 0700 owned by uid 1000; we widen it to o+rx so the
# entrypoint can later mitmweb-as-8181 reach the volume-mounted confdir
# without disturbing the cert files themselves.
RUN chmod o+rx /home/mitmproxy \
 && install -d -o 8181 -g 8181 /home/mitmproxy/.mitmproxy

COPY docker/mitmproxy-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Stay root for the entrypoint — it needs CAP_NET_ADMIN to flip iptables.
# It drops to uid 8181 with `gosu` before exec'ing mitmweb.
ENTRYPOINT ["/entrypoint.sh"]
