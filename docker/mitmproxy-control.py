#!/usr/bin/env python3
"""
Tiny control HTTP server for the mitmproxy bridge tap.

Why this lives inside the mitmproxy container:
  - It runs in the host network namespace (this container does), so it sees
    the same iptables/nft state the entrypoint installed.
  - It runs as root with NET_ADMIN, which the backend container deliberately
    does not. Letting only the mitmproxy container touch the host's nat
    table is a smaller blast radius than mounting docker.sock or sharing
    netns into the backend.

Endpoints (all require `Authorization: Bearer <MITM_WEB_PASSWORD>`):
  GET  /status         { enabled, bridge, gateway, listen_port }
  POST /enable         install the DNAT rules; idempotent
  POST /disable        remove them; idempotent

Listens on 0.0.0.0:8082 by default (host-network mode means this is the
host's :8082). The backend reaches it via host.docker.internal:8082.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Tuple

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))
CONTROL_PORT = int(os.environ.get("CONTROL_PORT", "8082"))
TOKEN = os.environ.get("MITM_WEB_PASSWORD", "headless-mitm")
REDROID_NETWORK = os.environ.get("REDROID_NETWORK", "docker_hl")


def log(msg: str) -> None:
    sys.stderr.write(f"\033[36m[mitm-control]\033[0m {msg}\n")
    sys.stderr.flush()


def sh(args: list[str]) -> Tuple[int, str, str]:
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def resolve_bridge() -> str | None:
    """Find the docker bridge for REDROID_NETWORK. Mirrors the shell logic
    in mitmproxy-entrypoint.sh.
    """
    # docker network inspect would be cleanest but the container doesn't
    # have docker CLI. The bridge is named br-<first 12 chars of network ID>.
    # We look at every br-* interface and check `ip -d link show` for the
    # network name in its metadata.
    try:
        out = subprocess.check_output(["ls", "/sys/class/net"], text=True)
    except subprocess.CalledProcessError:
        return None
    bridges = [n for n in out.split() if n.startswith("br-")]
    for name in bridges:
        rc, stdout, _ = sh(["ip", "-d", "link", "show", "dev", name])
        if rc == 0 and REDROID_NETWORK in stdout:
            return name
    # Fallback: if there's exactly one bridge, use it.
    return bridges[0] if len(bridges) == 1 else None


def bridge_gateway(bridge: str) -> str | None:
    rc, stdout, _ = sh(["ip", "-4", "-o", "addr", "show", "dev", bridge])
    if rc != 0:
        return None
    # Output looks like: `3: br-xxx    inet 172.18.0.1/16 brd ...`
    for tok in stdout.split():
        if "/" in tok and not tok.endswith("/8"):
            return tok.split("/")[0]
    return None


def rule_args(bridge: str, gateway: str, dport: int) -> list[str]:
    return [
        "-i", bridge,
        "-p", "tcp", "--dport", str(dport),
        "-j", "DNAT",
        "--to-destination", f"{gateway}:{LISTEN_PORT}",
    ]


def rule_present(bridge: str, gateway: str, dport: int) -> bool:
    """Use -C (check) to see if the rule exists. Returns True iff it does."""
    rc, _, _ = sh(["iptables-nft", "-t", "nat", "-C", "PREROUTING",
                   *rule_args(bridge, gateway, dport)])
    return rc == 0


def add_rule(bridge: str, gateway: str, dport: int) -> None:
    if rule_present(bridge, gateway, dport):
        return
    sh(["iptables-nft", "-t", "nat", "-A", "PREROUTING",
        *rule_args(bridge, gateway, dport)])


def del_rule(bridge: str, gateway: str, dport: int) -> None:
    # -D may run multiple times if there are duplicates from earlier
    # iterations. Loop until -C fails.
    while rule_present(bridge, gateway, dport):
        sh(["iptables-nft", "-t", "nat", "-D", "PREROUTING",
            *rule_args(bridge, gateway, dport)])


def status() -> dict:
    bridge = resolve_bridge()
    gateway = bridge_gateway(bridge) if bridge else None
    if not bridge or not gateway:
        return {
            "enabled": False,
            "bridge": bridge,
            "gateway": gateway,
            "listen_port": LISTEN_PORT,
            "reason": "bridge or gateway not resolvable",
        }
    enabled = (
        rule_present(bridge, gateway, 80)
        and rule_present(bridge, gateway, 443)
    )
    return {
        "enabled": enabled,
        "bridge": bridge,
        "gateway": gateway,
        "listen_port": LISTEN_PORT,
    }


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _check_auth(self) -> bool:
        h = self.headers.get("Authorization", "")
        if not h.startswith("Bearer "):
            self._send_json(401, {"error": "missing bearer token"})
            return False
        if h[len("Bearer "):] != TOKEN:
            self._send_json(403, {"error": "bad token"})
            return False
        return True

    def do_GET(self) -> None:
        if not self._check_auth():
            return
        if self.path != "/status":
            return self._send_json(404, {"error": "not found"})
        self._send_json(200, status())

    def do_POST(self) -> None:
        if not self._check_auth():
            return
        s = status()
        if "reason" in s:
            return self._send_json(503, s)
        bridge, gw = s["bridge"], s["gateway"]
        if self.path == "/enable":
            add_rule(bridge, gw, 80)
            add_rule(bridge, gw, 443)
            return self._send_json(200, status())
        if self.path == "/disable":
            del_rule(bridge, gw, 80)
            del_rule(bridge, gw, 443)
            return self._send_json(200, status())
        return self._send_json(404, {"error": "not found"})

    def log_message(self, fmt: str, *args) -> None:
        # Don't spam the parent process's stderr with one line per request.
        log(fmt % args)


def main() -> None:
    log(f"control server listening on :{CONTROL_PORT} (token via Bearer)")
    server = ThreadingHTTPServer(("0.0.0.0", CONTROL_PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
