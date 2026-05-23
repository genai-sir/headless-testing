// GET /api/health
//
// 200 (`{ok:true,...}`) only if every layer of the stealth stack is alive:
//   adb        : `adb devices` shows our serial in `device` state
//   magisk     : /sbin/su -v reports a MAGISK version
//   lspd       : the LSPosed daemon process is up
//   stealthEnb : com.headless.mockloc is enabled in modules_config.db
//
// 503 otherwise, with `{ok:false, status:{...}, failed:[...]}` so dashboards
// and orchestrators (docker healthcheck, Synology monitor, alertmanager) can
// trigger on the same signal.
//
// Cheap: only adb shell roundtrips, no extra deps.

import { Router } from "express";
import { adb, shell } from "../lib/adb.js";
import { config } from "../config.js";

const router = Router();

async function adbConnected() {
  const r = await adb(["devices"], { timeoutMs: 5000 });
  if (!r.ok) return false;
  const want = config.adbSerial;
  if (!want) return /\bdevice\b/.test(r.stdout);
  // serial line looks like "redroid:5555\tdevice"
  return new RegExp(`^${want}\\s+device\\b`, "m").test(r.stdout);
}

async function magiskUp() {
  const r = await shell("/sbin/su -v 2>/dev/null", { timeoutMs: 5000 });
  return r.ok && /MAGISK/i.test(r.stdout);
}

async function lspdUp() {
  const r = await shell("pidof lspd 2>/dev/null", { timeoutMs: 5000 });
  return r.ok && /^\d+/.test(r.stdout);
}

async function stealthModuleEnabled() {
  const r = await shell(
    `/sbin/su -c "sqlite3 /data/adb/lspd/config/modules_config.db \\"SELECT enabled FROM modules WHERE module_pkg_name = 'com.headless.mockloc';\\""`,
    { timeoutMs: 5000 },
  );
  return r.ok && r.stdout.trim() === "1";
}

router.get("/", async (_req, res) => {
  const [adbOk, magiskOk, lspdOk, stealthOk] = await Promise.all([
    adbConnected(),
    magiskUp(),
    lspdUp(),
    stealthModuleEnabled(),
  ]);

  const status = { adb: adbOk, magisk: magiskOk, lspd: lspdOk, stealthEnabled: stealthOk };
  const failed = Object.entries(status).filter(([, ok]) => !ok).map(([k]) => k);
  const ok = failed.length === 0;

  res.status(ok ? 200 : 503).json({ ok, status, failed });
});

export default router;
