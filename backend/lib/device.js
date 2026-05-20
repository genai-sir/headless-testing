import { adb, shell, getProp, isRooted, tryRoot, deviceList } from "./adb.js";
import { config } from "../config.js";

export async function deviceInfo() {
  const list = await deviceList();
  const target = config.adbSerial
    ? list.find((d) => d.serial === config.adbSerial)
    : list[0];

  if (!target || target.state !== "device") {
    return {
      connected: false,
      backendType: config.backendType,
      devices: list,
    };
  }

  const [brand, model, release, sdk, abi, fingerprint] = await Promise.all([
    getProp("ro.product.brand"),
    getProp("ro.product.model"),
    getProp("ro.build.version.release"),
    getProp("ro.build.version.sdk"),
    getProp("ro.product.cpu.abi"),
    getProp("ro.build.fingerprint"),
  ]);

  const rooted = await isRooted();
  const bootCompleted = (await getProp("sys.boot_completed")) === "1";

  return {
    connected: true,
    backendType: config.backendType,
    serial: target.serial,
    state: target.state,
    info: target.info,
    rooted,
    bootCompleted,
    properties: {
      brand,
      model,
      androidVersion: release,
      sdk: Number(sdk) || sdk,
      abi,
      fingerprint,
    },
  };
}

export async function ensureRoot() {
  if (await isRooted()) return true;
  return await tryRoot();
}

export async function installApk(localPath) {
  // -r reinstall, -g grant all runtime perms, -t allow test packages,
  // -d allow downgrade (helps when iterating).
  const r = await adb(["install", "-r", "-g", "-t", "-d", localPath], {
    timeoutMs: 300000,
  });
  // adb install prints "Success" on stdout on success in newer versions.
  return {
    ok: r.ok && /Success/i.test(r.stdout + r.stderr),
    stdout: r.stdout,
    stderr: r.stderr,
    code: r.code,
  };
}

export async function runShell(cmd) {
  // root the shell if we have it.
  return shell(cmd, { timeoutMs: 60000 });
}
