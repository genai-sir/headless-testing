// GET  /api/proxy/status   layered status (mitmweb reachable, capture mode)
// GET  /api/proxy/flows    recent HTTP flows captured by mitmproxy, normalized
// GET  /api/proxy/flows/:id  full flow JSON straight from mitmweb
// DELETE /api/proxy/flows  clear mitmproxy's flow buffer
//
// Capture model: transparent. The mitmproxy container joins redroid's network
// namespace and installs iptables OUTPUT REDIRECT rules for ports 80 and 443.
// Apps inside redroid don't need to know about a proxy — all HTTPS goes
// through mitmproxy as long as the system CA cert is trusted (which the
// install-mitm-ca.sh script handles).
//
// We no longer expose a "set http_proxy on the device" toggle; that mode was
// unreliable (Chrome/QUIC/OkHttp variants ignored it) and is now redundant.

import { Router } from "express";
import { shell } from "../lib/adb.js";
import { config } from "../config.js";

const router = Router();

const MITM = config.mitm;

async function fetchMitm(path, init) {
  const url = `${MITM.apiUrl}${path}`;
  const headers = {
    accept: "application/json",
    Authorization: `Bearer ${MITM.webPassword}`,
    ...(init?.headers || {}),
  };
  const r = await fetch(url, { ...(init || {}), headers });
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new Error(`mitmweb ${path}: ${r.status} ${text.slice(0, 200)}`);
  }
  return r;
}

async function mitmReachable() {
  try {
    const r = await fetch(`${MITM.apiUrl}/flows`, {
      signal: AbortSignal.timeout(2000),
      headers: { Authorization: `Bearer ${MITM.webPassword}` },
    });
    return r.ok;
  } catch {
    return false;
  }
}

// The control endpoint lives at the same host as mitmweb, on port 8082.
// It manipulates iptables — that's why it has its own process inside the
// mitmproxy container (root + NET_ADMIN), separate from mitmweb (uid 8181).
function controlUrl(path) {
  // MITM.apiUrl is something like `http://host.docker.internal:8081`.
  // Swap the port to 8082 for the control endpoint.
  return MITM.apiUrl.replace(/:\d+$/, ":8082") + path;
}

async function fetchControl(path, init) {
  const r = await fetch(controlUrl(path), {
    ...(init || {}),
    headers: {
      accept: "application/json",
      Authorization: `Bearer ${MITM.webPassword}`,
      ...(init?.headers || {}),
    },
    signal: AbortSignal.timeout(4000),
  });
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new Error(`control ${path}: ${r.status} ${text.slice(0, 200)}`);
  }
  return r.json();
}

async function captureStatus() {
  try {
    return await fetchControl("/status");
  } catch {
    return { enabled: false, reachable: false };
  }
}

router.get("/status", async (_req, res) => {
  const [reachable, legacyDeviceProxy, capture] = await Promise.all([
    mitmReachable(),
    // Just to surface any *user-set* http_proxy that's still hanging around
    // from the old global-proxy mode. We don't drive it anymore.
    shell("settings get global http_proxy").then((r) => {
      const v = (r.stdout || "").trim();
      return !v || v === "null" ? null : v;
    }).catch(() => null),
    captureStatus(),
  ]);
  res.json({
    // Two booleans the dashboard cares about:
    //   mitmReachable: is the proxy daemon alive?
    //   capture.enabled: are the iptables rules currently routing traffic
    //                    to it? (toggleable independently)
    capture,
    captureMode: "transparent",
    mitmReachable: reachable,
    legacyDeviceProxy,
    // True iff *both* mitmproxy is alive AND iptables is currently
    // routing traffic to it. Dashboard uses this for the "capturing" pill.
    enabled: reachable && !!capture?.enabled,
    // Token the dashboard appends to the mitmweb iframe URL so the iframe
    // can authenticate against mitmweb without a separate login prompt. The
    // dashboard itself is expected to be auth-guarded at the edge, so this
    // is no worse than the existing trust boundary.
    webToken: MITM.webPassword,
  });
});

// Toggle the iptables DNAT rules on/off. mitmproxy keeps running either
// way, so the flow buffer survives — only new traffic is or isn't being
// redirected. POST body: { "enabled": true } / { "enabled": false }.
router.post("/toggle", async (req, res, next) => {
  try {
    const enabled = req.body?.enabled === true;
    const out = await fetchControl(enabled ? "/enable" : "/disable", { method: "POST" });
    res.json({ ok: true, capture: out });
  } catch (err) {
    next(err);
  }
});

router.get("/flows", async (req, res, next) => {
  try {
    const r = await fetchMitm("/flows");
    const flows = await r.json();
    const limit = Math.min(Number(req.query.limit) || 100, 500);
    const slice = flows.slice(-limit).reverse();
    const normalized = slice.map((f) => {
      const rq = f.request || {};
      const resp = f.response || null;
      return {
        id: f.id,
        timestamp: rq.timestamp_start || f.timestamp_created,
        method: rq.method,
        scheme: rq.scheme,
        host: rq.pretty_host || rq.host,
        port: rq.port,
        path: rq.path,
        httpVersion: rq.http_version,
        status: resp?.status_code ?? null,
        reason: resp?.reason ?? null,
        contentType:
          resp?.headers?.find?.((h) => /content-type/i.test(h[0]))?.[1] ||
          rq.headers?.find?.((h) => /content-type/i.test(h[0]))?.[1] ||
          null,
        respSize: resp?.contentLength ?? 0,
        marked: !!f.marked,
      };
    });
    res.json({ count: normalized.length, flows: normalized });
  } catch (err) {
    next(err);
  }
});

router.get("/flows/:id", async (req, res, next) => {
  try {
    const r = await fetchMitm(`/flows/${encodeURIComponent(req.params.id)}`);
    res.json(await r.json());
  } catch (err) {
    next(err);
  }
});

router.delete("/flows", async (_req, res, next) => {
  try {
    await fetchMitm("/clear", { method: "POST" });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// Clear any stale settings global http_proxy left over from the old mode.
// Idempotent; safe to call even if nothing is set.
router.post("/clear-legacy-proxy", async (_req, res) => {
  await shell("settings put global http_proxy :0");
  await shell("settings delete global http_proxy");
  await shell("settings delete global global_http_proxy_host");
  await shell("settings delete global global_http_proxy_port");
  res.json({ ok: true });
});

export default router;
