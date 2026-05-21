// GET /api/stealth -> layered status report of stealth components.
//
// Layer detection is best-effort and read-only:
//   magisk     : /data/adb/magisk/util_functions.sh exists
//   lsposed    : org.lsposed.manager installed
//   stealthApk : com.headless.mockloc installed
//   mockLocAop : appop android:mock_location is "allow" for our pkg
//
// We do not (yet) run a live hook test from an in-device probe. That would
// require shipping a tiny instrumented test apk; deferred.

import { Router } from "express";
import { shell } from "../lib/adb.js";

const router = Router();

async function check(cmd) {
  const r = await shell(cmd);
  return { ok: r.ok && !!r.stdout && !/not found|No such/i.test(r.stderr), stdout: r.stdout, stderr: r.stderr };
}

router.get("/", async (_req, res) => {
  const [magisk, lsposed, stealthApk, appop] = await Promise.all([
    check("ls -d /data/adb/magisk 2>/dev/null && echo present"),
    check("pm list packages org.lsposed.manager"),
    check("pm list packages com.headless.mockloc"),
    check("cmd appops get com.headless.mockloc android:mock_location 2>/dev/null"),
  ]);

  const status = {
    magisk: magisk.ok,
    lsposed: lsposed.ok && /org\.lsposed\.manager/.test(lsposed.stdout),
    stealthApk: stealthApk.ok && /com\.headless\.mockloc/.test(stealthApk.stdout),
    mockLocAppop: /allow/i.test(appop.stdout),
  };

  // Reachable summary line for the UI pill.
  let summary;
  if (status.magisk && status.lsposed && status.stealthApk && status.mockLocAppop) {
    summary = "stealth active";
  } else if (status.stealthApk && status.mockLocAppop) {
    summary = "mock loc only (no LSPosed → apps will detect)";
  } else if (status.stealthApk) {
    summary = "stealth APK installed; appop not granted";
  } else {
    summary = "stealth not installed";
  }

  res.json({ summary, status });
});

export default router;
