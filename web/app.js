const $ = (sel) => document.querySelector(sel);

const statusPill = $("#status-pill");
const deviceInfoEl = $("#device-info");

let cfg = null;

async function api(path, opts = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...opts,
  });
  return res.json();
}

function setStatus(text, kind = "") {
  statusPill.className = "pill" + (kind ? " " + kind : "");
  statusPill.textContent = text;
}

function fmtKv(obj, depth = 0) {
  return Object.entries(obj)
    .map(([k, v]) => {
      if (v != null && typeof v === "object") {
        return `${"  ".repeat(depth)}<b>${k}</b>:\n${fmtKv(v, depth + 1)}`;
      }
      return `${"  ".repeat(depth)}<b>${k}</b>: ${v}`;
    })
    .join("\n");
}

async function refreshDevice() {
  const info = await api("/api/device");
  deviceInfoEl.innerHTML = fmtKv(info);
  if (!info.connected) {
    setStatus(`no device (${info.backendType})`, "bad");
  } else if (!info.bootCompleted) {
    setStatus("booting…", "warn");
  } else if (info.rooted) {
    setStatus(`rooted · ${info.properties.brand} ${info.properties.model} · Android ${info.properties.androidVersion}`, "ok");
  } else {
    setStatus(`connected (not root) · Android ${info.properties.androidVersion}`, "warn");
  }
}

async function loadConfig() {
  cfg = await api("/api/config");
  // Embed ws-scrcpy. ws-scrcpy auto-picks the first device.
  $("#viewer").src = cfg.wsScrcpyUrl;
  $("#open-viewer").onclick = () => window.open(cfg.wsScrcpyUrl, "_blank");
}

// ---------- root ----------
$("#btn-refresh").onclick = refreshDevice;
$("#btn-root").onclick = async () => {
  setStatus("requesting root…", "warn");
  await api("/api/device/root", { method: "POST" });
  await refreshDevice();
};

// ---------- APK upload ----------
const dropzone = $("#dropzone");
const apkInput = $("#apk-file");
const apkOutput = $("#apk-output");

function uploadApk(file) {
  apkOutput.textContent = `uploading ${file.name} (${(file.size / 1e6).toFixed(1)} MB)…`;
  const fd = new FormData();
  fd.append("apk", file);
  return fetch("/api/apk", { method: "POST", body: fd })
    .then((r) => r.json())
    .then((r) => {
      const msg = r.ok ? "installed ok" : "install FAILED";
      apkOutput.textContent =
        `${msg}\n\n` +
        `file: ${r.file}\n` +
        `size: ${(r.size / 1e6).toFixed(1)} MB\n\n` +
        `stdout:\n${r.install?.stdout || ""}\n` +
        (r.install?.stderr ? `\nstderr:\n${r.install.stderr}` : "");
      refreshDevice();
    })
    .catch((e) => (apkOutput.textContent = `error: ${e.message}`));
}

dropzone.onclick = () => apkInput.click();
apkInput.onchange = () => apkInput.files[0] && uploadApk(apkInput.files[0]);

["dragenter", "dragover"].forEach((ev) =>
  dropzone.addEventListener(ev, (e) => {
    e.preventDefault();
    dropzone.classList.add("drag");
  }),
);
["dragleave", "drop"].forEach((ev) =>
  dropzone.addEventListener(ev, (e) => {
    e.preventDefault();
    dropzone.classList.remove("drag");
  }),
);
dropzone.addEventListener("drop", (e) => {
  const file = e.dataTransfer.files?.[0];
  if (file) uploadApk(file);
});

// ---------- location ----------
const latEl = $("#lat");
const lngEl = $("#lng");
const locOutput = $("#loc-output");

document.querySelectorAll(".presets button").forEach((b) => {
  b.onclick = () => {
    latEl.value = b.dataset.lat;
    lngEl.value = b.dataset.lng;
  };
});

$("#btn-set-loc").onclick = async () => {
  const lat = parseFloat(latEl.value);
  const lng = parseFloat(lngEl.value);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    locOutput.textContent = "lat and lng required";
    return;
  }
  locOutput.textContent = "setting…";
  const r = await api("/api/location", {
    method: "POST",
    body: JSON.stringify({ lat, lng }),
  });
  locOutput.textContent =
    (r.ok ? "ok" : "FAILED") +
    `  via ${r.via}\n` +
    (r.detail?.error ? `error: ${r.detail.error}\n` : "") +
    (r.detail?.output ? `\n${r.detail.output}` : "");
};

// ---------- shell ----------
$("#shell-form").onsubmit = async (e) => {
  e.preventDefault();
  const cmd = $("#shell-cmd").value.trim();
  if (!cmd) return;
  const out = $("#shell-output");
  out.textContent = `$ ${cmd}\n…`;
  const r = await api("/api/shell", {
    method: "POST",
    body: JSON.stringify({ cmd }),
  });
  out.textContent =
    `$ ${cmd}\n` +
    (r.stdout ? r.stdout + "\n" : "") +
    (r.stderr ? `[stderr]\n${r.stderr}\n` : "") +
    `[exit ${r.code}${r.timedOut ? " · timed out" : ""}]`;
};

// ---------- logcat ----------
let logcatEs = null;
const logcatBtn = $("#btn-logcat-toggle");
const logcatOut = $("#logcat-output");

logcatBtn.onclick = () => {
  if (logcatEs) {
    logcatEs.close();
    logcatEs = null;
    logcatBtn.textContent = "start";
    return;
  }
  const tag = $("#logcat-tag").value.trim();
  const url = "/api/logcat/stream" + (tag ? `?tag=${encodeURIComponent(tag)}` : "");
  logcatEs = new EventSource(url);
  logcatBtn.textContent = "stop";
  logcatEs.onmessage = (e) => {
    logcatOut.textContent += e.data + "\n";
    logcatOut.scrollTop = logcatOut.scrollHeight;
  };
  logcatEs.onerror = () => {
    logcatBtn.textContent = "start";
    if (logcatEs) logcatEs.close();
    logcatEs = null;
  };
};

$("#btn-logcat-clear").onclick = () => (logcatOut.textContent = "");

// ---------- stealth ----------
const stealthList = $("#stealth-list");
const stealthSummary = $("#stealth-summary");

async function refreshStealth() {
  let s;
  try {
    s = await api("/api/stealth");
  } catch {
    return;
  }
  stealthList.querySelectorAll("li").forEach((li) => {
    const ok = !!s.status[li.dataset.key];
    li.classList.toggle("ok", ok);
    li.classList.toggle("bad", !ok);
  });
  const allOn = Object.values(s.status).every(Boolean);
  const mockOnly = s.status.stealthApk && s.status.mockLocAppop && !s.status.lsposed;
  stealthSummary.textContent = s.summary;
  stealthSummary.className = allOn
    ? "ok"
    : mockOnly
      ? "warn"
      : "bad";
}

// ---------- scope ----------
const scopeList = $("#scope-list");
const scopeFilter = $("#scope-filter");
const scopeSystem = $("#scope-system");
const scopeApply = $("#scope-apply");
const scopePending = $("#scope-pending");
const scopeSummary = $("#scope-summary");

let scopeDirty = false;
let scopeRefreshTimer = null;

function setScopeDirty(dirty) {
  scopeDirty = dirty;
  scopeApply.disabled = !dirty;
  scopePending.textContent = dirty ? "pending changes — reboot to apply" : "";
}

async function refreshScope() {
  let data;
  try {
    const sys = scopeSystem.checked ? "?system=true" : "";
    data = await api("/api/scope" + sys);
  } catch {
    return;
  }
  if (!data.ok) {
    scopeList.innerHTML =
      `<li class="empty">${data.error || "scope unavailable"}</li>`;
    scopeSummary.textContent = "";
    return;
  }
  scopeSummary.textContent = `${data.counts.scoped} of ${data.counts.installed} apps`;
  scopeSummary.className = data.counts.scoped > 0 ? "ok" : "dim";

  const filter = scopeFilter.value.toLowerCase();
  scopeList.innerHTML = "";
  for (const { pkg, scoped, installed } of data.apps) {
    const li = document.createElement("li");
    if (!installed) li.classList.add("uninstalled");
    if (filter && !pkg.toLowerCase().includes(filter)) li.classList.add("hidden");
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = scoped;
    cb.dataset.pkg = pkg;
    cb.addEventListener("change", onScopeToggle);
    const label = document.createElement("label");
    label.appendChild(cb);
    const span = document.createElement("span");
    span.textContent = pkg;
    label.appendChild(span);
    li.appendChild(label);
    scopeList.appendChild(li);
  }
  if (data.apps.length === 0) {
    scopeList.innerHTML = `<li class="empty">no apps</li>`;
  }
}

async function onScopeToggle(e) {
  const pkg = e.target.dataset.pkg;
  const url = e.target.checked ? "/api/scope/add" : "/api/scope/remove";
  e.target.disabled = true;
  try {
    await api(url, {
      method: "POST",
      body: JSON.stringify({ pkg }),
    });
    setScopeDirty(true);
  } finally {
    e.target.disabled = false;
  }
}

scopeFilter.addEventListener("input", () => refreshScope());
scopeSystem.addEventListener("change", () => refreshScope());
scopeApply.addEventListener("click", async () => {
  if (!confirm("Reboot the device to apply scope changes?")) return;
  scopeApply.disabled = true;
  scopeApply.textContent = "rebooting…";
  scopePending.textContent = "waiting for device to come back";
  try {
    await api("/api/scope/apply", { method: "POST" });
  } catch {}
  // Poll /api/device until bootCompleted.
  const start = Date.now();
  const poll = setInterval(async () => {
    const dev = await api("/api/device").catch(() => null);
    if (dev?.bootCompleted) {
      clearInterval(poll);
      scopeApply.textContent = "apply (reboot)";
      setScopeDirty(false);
      refreshScope();
      refreshDevice();
      refreshStealth();
    } else if (Date.now() - start > 120000) {
      clearInterval(poll);
      scopeApply.textContent = "apply (reboot)";
      scopePending.textContent = "device didn't come back in 2 min — check manually";
    }
  }, 2000);
});

// ---------- proxy / traffic ----------
const proxyToggle = $("#proxy-toggle");
const proxyClear = $("#proxy-clear");
const proxyOpen = $("#proxy-open");
const proxySummary = $("#proxy-summary");
const flowList = $("#flow-list");
const mitmwebFrame = $("#mitmweb");
const mitmwebWrap = $("#mitmweb-wrap");

let lastProxyStatus = null;
let mitmwebUrlCache = null;

function mitmwebUrl(token) {
  // Same host as the dashboard, port 8081. Cached so we don't recompute.
  if (mitmwebUrlCache) return mitmwebUrlCache;
  const loc = window.location;
  const t = token ? `?token=${encodeURIComponent(token)}` : "";
  mitmwebUrlCache = `${loc.protocol}//${loc.hostname}:8081/${t}`;
  return mitmwebUrlCache;
}

function setProxyPill(s) {
  if (!s.mitmReachable) {
    proxySummary.textContent = "tap unreachable";
    proxySummary.className = "dim bad";
    proxyToggle.disabled = true;
    return;
  }
  proxyToggle.disabled = false;
  proxyToggle.checked = !!s.capture?.enabled;
  if (s.legacyDeviceProxy) {
    proxySummary.textContent = `legacy http_proxy=${s.legacyDeviceProxy} (clear it)`;
    proxySummary.className = "dim warn";
  } else if (s.capture?.enabled) {
    proxySummary.textContent = "capturing";
    proxySummary.className = "dim ok";
  } else {
    proxySummary.textContent = "paused";
    proxySummary.className = "dim";
  }
}

async function refreshProxyStatus() {
  try {
    const s = await api("/api/proxy/status");
    lastProxyStatus = s;
    setProxyPill(s);
    if (s.webToken && !mitmwebUrlCache) mitmwebUrl(s.webToken);
  } catch (e) {
    proxySummary.textContent = "error";
    proxySummary.className = "dim bad";
  }
}

function renderFlows(flows) {
  if (!flows.length) {
    flowList.innerHTML = '<li class="empty">no traffic captured</li>';
    return;
  }
  flowList.innerHTML = flows
    .map((f) => {
      const status = f.status ? `<span class="status s${Math.floor(f.status / 100)}xx">${f.status}</span>` : '<span class="status pending">…</span>';
      const method = `<span class="method m-${(f.method || "?").toLowerCase()}">${f.method || "?"}</span>`;
      const url = `${f.scheme || "http"}://${f.host || "?"}${f.path || ""}`;
      // Truncate display path; full URL on title.
      const display = url.length > 100 ? url.slice(0, 97) + "…" : url;
      return `<li title="${url.replace(/"/g, "&quot;")}">${method}${status}<span class="url">${display}</span></li>`;
    })
    .join("");
}

async function refreshFlows() {
  // Only fetch if mitm is reachable, to avoid noisy error spam.
  if (!lastProxyStatus?.mitmReachable) return;
  try {
    const r = await api("/api/proxy/flows?limit=50");
    renderFlows(r.flows || []);
  } catch {
    // surface only via the proxy pill on the next status tick
  }
}

proxyToggle.addEventListener("change", async () => {
  proxyToggle.disabled = true;
  try {
    await api("/api/proxy/toggle", {
      method: "POST",
      body: JSON.stringify({ enabled: proxyToggle.checked }),
    });
  } finally {
    // refreshProxyStatus re-enables and re-syncs the checkbox to reality.
    await refreshProxyStatus();
  }
});

proxyClear.addEventListener("click", async () => {
  await api("/api/proxy/flows", { method: "DELETE" });
  renderFlows([]);
});

proxyOpen.addEventListener("click", () => {
  const t = lastProxyStatus?.webToken;
  window.open(mitmwebUrl(t), "_blank");
});

// Lazy-load the iframe only when the user expands the mitmweb section.
// Avoids a heavyweight load on every dashboard open.
mitmwebWrap.addEventListener("toggle", () => {
  if (mitmwebWrap.open && mitmwebFrame.src === "about:blank") {
    const t = lastProxyStatus?.webToken;
    mitmwebFrame.src = mitmwebUrl(t);
  }
});

// ---------- boot ----------
loadConfig().then(refreshDevice);
setInterval(refreshDevice, 5000);
refreshStealth();
setInterval(refreshStealth, 8000);
refreshScope();
scopeRefreshTimer = setInterval(refreshScope, 10000);
refreshProxyStatus();
setInterval(refreshProxyStatus, 6000);
refreshFlows();
setInterval(refreshFlows, 2000);
