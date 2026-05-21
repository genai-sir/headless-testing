// /api/scope — manage which apps the headless-android stealth module hooks
// into. Bypasses LSPosed Manager UI by writing to the daemon's SQLite DB.

import { Router } from "express";
import { adb, shell } from "../lib/adb.js";

const router = Router();

const MODULE_PKG = "com.headless.mockloc";
const DB_PATH = "/data/adb/lspd/config/modules_config.db";
const PKG_NAME_RE = /^[a-zA-Z][a-zA-Z0-9._]{0,254}$/;

// ---- sqlite via adb shell stdin -------------------------------------------
// Avoids escaping hell. Sends SQL through a HEREDOC into `su -c sqlite3`.
async function dbExec(sql) {
  const script = `su -c 'sqlite3 ${DB_PATH}' <<'__SQL__'
${sql}
__SQL__
`;
  return adb(["shell"], { stdin: script, timeoutMs: 15000 });
}

async function moduleRow() {
  const r = await dbExec(
    `SELECT mid, enabled FROM modules WHERE module_pkg_name='${MODULE_PKG}';`,
  );
  if (!r.ok || !r.stdout) return null;
  const [mid, enabled] = r.stdout.split("|");
  return { mid: Number(mid), enabled: enabled === "1" };
}

async function scopedPackages(mid) {
  const r = await dbExec(`SELECT app_pkg_name FROM scope WHERE mid=${mid};`);
  if (!r.ok) return [];
  return r.stdout.split("\n").map((s) => s.trim()).filter(Boolean);
}

async function installedPackages({ includeSystem = false } = {}) {
  const args = ["shell", "pm", "list", "packages"];
  if (!includeSystem) args.push("-3");
  const r = await adb(args);
  if (!r.ok) return [];
  return r.stdout
    .split("\n")
    .map((line) => line.replace(/^package:/, "").trim())
    .filter(Boolean)
    .sort();
}

// ---- GET / ----------------------------------------------------------------
router.get("/", async (req, res) => {
  const includeSystem = req.query.system === "true";
  const mod = await moduleRow();
  if (!mod) {
    return res.json({
      ok: false,
      error: "stealth module not registered yet — run scripts/install-magisk-avd.sh",
    });
  }
  const [scoped, apps] = await Promise.all([
    scopedPackages(mod.mid),
    installedPackages({ includeSystem }),
  ]);
  const scopedSet = new Set(scoped);
  // Always include the union: every installed app, plus anything in scope
  // that's been uninstalled (so the user can clean it up).
  const seen = new Set();
  const merged = [];
  for (const pkg of apps) {
    if (seen.has(pkg)) continue;
    seen.add(pkg);
    merged.push({ pkg, scoped: scopedSet.has(pkg), installed: true });
  }
  for (const pkg of scoped) {
    if (seen.has(pkg)) continue;
    seen.add(pkg);
    merged.push({ pkg, scoped: true, installed: false });
  }
  res.json({
    ok: true,
    module: { ...mod, pkg: MODULE_PKG },
    apps: merged,
    counts: { installed: apps.length, scoped: scoped.length },
    includeSystem,
  });
});

// ---- POST /add ------------------------------------------------------------
router.post("/add", async (req, res) => {
  const { pkg } = req.body || {};
  if (!PKG_NAME_RE.test(pkg || "")) {
    return res.status(400).json({ ok: false, error: "invalid package name" });
  }
  const mod = await moduleRow();
  if (!mod) {
    return res.status(500).json({ ok: false, error: "module not registered" });
  }
  await dbExec(
    `INSERT OR IGNORE INTO scope (mid, app_pkg_name, user_id) VALUES (${mod.mid}, '${pkg}', 0);`,
  );
  res.json({ ok: true, pkg });
});

// ---- POST /remove ---------------------------------------------------------
router.post("/remove", async (req, res) => {
  const { pkg } = req.body || {};
  if (!PKG_NAME_RE.test(pkg || "")) {
    return res.status(400).json({ ok: false, error: "invalid package name" });
  }
  await dbExec(`DELETE FROM scope WHERE app_pkg_name='${pkg}';`);
  res.json({ ok: true, pkg });
});

// ---- POST /enable ---------------------------------------------------------
// Toggle the module's enabled flag (separate from scope rows).
router.post("/enable", async (req, res) => {
  const enabled = !!req.body?.enabled;
  await dbExec(
    `UPDATE modules SET enabled=${enabled ? 1 : 0} WHERE module_pkg_name='${MODULE_PKG}';`,
  );
  res.json({ ok: true, enabled });
});

// ---- POST /apply ----------------------------------------------------------
// Reboot the device, then re-grant the mock_location appop (which resets
// across reboots). Doesn't wait for boot — UI polls /api/device.
router.post("/apply", async (_req, res) => {
  res.json({ ok: true, message: "reboot triggered — page will reload when device is back" });
  // Fire-and-forget reboot. Re-grant appop ~30s later.
  shell("reboot").catch(() => {});
  setTimeout(async () => {
    for (let i = 0; i < 60; i++) {
      const r = await shell("getprop sys.boot_completed");
      if (r.ok && r.stdout.trim() === "1") {
        await adb(["root"]).catch(() => {});
        await shell(`cmd appops set ${MODULE_PKG} android:mock_location allow`);
        return;
      }
      await new Promise((r) => setTimeout(r, 2000));
    }
  }, 2000);
});

export default router;
