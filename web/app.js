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

// ---------- boot ----------
loadConfig().then(refreshDevice);
setInterval(refreshDevice, 5000);
refreshStealth();
setInterval(refreshStealth, 8000);
