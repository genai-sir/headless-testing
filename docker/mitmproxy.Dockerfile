# mitmproxy in transparent-tap mode for redroid.
#
# Why we extend the upstream image:
#   1. We need `iptables` so the entrypoint can install REDIRECT rules.
#   2. We need a known non-colliding uid (8181) so future filter rules with
#      `-m owner --uid-owner` won't collide with Android's system uid 1000.
#
# The compose file runs this container with `network_mode: host`. Our entrypoint
# installs `iptables -t nat -A PREROUTING` rules on the docker bridge that
# carries redroid's traffic — so packets emitted by Android apps hit the rule
# in the host kernel (where SO_ORIGINAL_DST is preserved). mitmproxy listens
# in transparent mode and reads SO_ORIGINAL_DST to learn the real upstream.

FROM mitmproxy/mitmproxy:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 gosu \
 && rm -rf /var/lib/apt/lists/* \
 # Modern host kernels (Debian 12+, Ubuntu 22+) drive netfilter via nftables
 # and docker writes its own bridge/NAT rules into the same nft tables.
 # We must use the nft-backed iptables binary so our PREROUTING REDIRECT
 # composes with docker's existing chains — the legacy binary writes into a
 # parallel ruleset that the kernel evaluates but docker's rules can shadow.
 && update-alternatives --set iptables /usr/sbin/iptables-nft \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-nft \
 && useradd -u 8181 -m -d /home/mitm-tap mitm-tap

# Persist the same /home/mitmproxy/.mitmproxy path the mitmweb tooling expects
# (CA cert location) but make it traversable by uid 8181. The upstream image
# ships /home/mitmproxy as 0700 owned by uid 1000; we widen it to o+rx so the
# entrypoint can later mitmweb-as-8181 reach the volume-mounted confdir
# without disturbing the cert files themselves.
RUN chmod o+rx /home/mitmproxy \
 && install -d -o 8181 -g 8181 /home/mitmproxy/.mitmproxy

COPY docker/mitmproxy-entrypoint.sh /entrypoint.sh
COPY docker/mitmproxy-control.py /control.py
RUN chmod +x /entrypoint.sh /control.py

# Stay root for the entrypoint — it needs CAP_NET_ADMIN to flip iptables.
# It drops to uid 8181 with `gosu` before exec'ing mitmweb.
ENTRYPOINT ["/entrypoint.sh"]
