import { spawn } from "node:child_process";
import { config } from "../config.js";

function args(extra) {
  const base = [];
  if (config.adbSerial) base.push("-s", config.adbSerial);
  return [...base, ...extra];
}

export function adb(extra, { stdin, timeoutMs = 60000 } = {}) {
  return new Promise((resolve) => {
    const proc = spawn(config.adbPath, args(extra), {
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let killed = false;

    const timer = setTimeout(() => {
      killed = true;
      proc.kill("SIGKILL");
    }, timeoutMs);

    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));
    proc.on("close", (code) => {
      clearTimeout(timer);
      resolve({
        ok: code === 0 && !killed,
        code,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        timedOut: killed,
      });
    });

    if (stdin != null) proc.stdin.end(stdin);
    else proc.stdin.end();
  });
}

export async function shell(cmd, opts) {
  return adb(["shell", cmd], opts);
}

export async function getProp(name) {
  const r = await shell(`getprop ${name}`);
  return r.ok ? r.stdout : "";
}

export async function waitForBoot(timeoutMs = 180000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const v = await getProp("sys.boot_completed");
    if (v === "1") return true;
    await new Promise((r) => setTimeout(r, 1500));
  }
  return false;
}

export async function isRooted() {
  const r = await shell("id");
  return r.ok && /uid=0\(root\)/.test(r.stdout);
}

export async function tryRoot() {
  const r = await adb(["root"], { timeoutMs: 15000 });
  // Returns "adbd is already running as root" or "restarting adbd as root"
  if (!r.ok) return false;
  // wait for adbd to come back
  await new Promise((res) => setTimeout(res, 1500));
  await adb(["wait-for-device"], { timeoutMs: 15000 });
  return await isRooted();
}

export async function deviceList() {
  const r = await adb(["devices", "-l"]);
  if (!r.ok) return [];
  return r.stdout
    .split("\n")
    .slice(1)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [serial, state, ...rest] = line.split(/\s+/);
      return { serial, state, info: rest.join(" ") };
    });
}
