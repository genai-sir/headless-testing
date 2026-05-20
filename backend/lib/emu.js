// AVD-only: talk to the emulator console.
// Each running AVD listens on a TCP port (default 5554). We send commands like:
//   auth <token>\n
//   geo fix <lng> <lat> [alt]\n
//
// The token lives at ~/.emulator_console_auth_token.

import { createConnection } from "node:net";
import { readFileSync, existsSync } from "node:fs";
import { config } from "../config.js";

function emulatorPortFromSerial(serial) {
  // serial is like "emulator-5554"
  const m = /emulator-(\d+)/.exec(serial || "");
  return m ? Number(m[1]) : 5554;
}

function loadToken() {
  if (!existsSync(config.emulatorAuthTokenPath)) return "";
  return readFileSync(config.emulatorAuthTokenPath, "utf8").trim();
}

export function emuCommand(cmd, { port, timeoutMs = 5000 } = {}) {
  return new Promise((resolve) => {
    const p = port ?? emulatorPortFromSerial(config.adbSerial);
    const token = loadToken();
    const sock = createConnection({ host: "127.0.0.1", port: p });
    let out = "";
    let done = false;
    const finish = (ok, err) => {
      if (done) return;
      done = true;
      sock.destroy();
      resolve({ ok, output: out, error: err || null });
    };
    const timer = setTimeout(() => finish(false, "timeout"), timeoutMs);

    sock.on("data", (d) => {
      out += d.toString();
      // Send auth once we see the banner.
      if (out.includes("OK") && !sock._sentAuth && token) {
        sock._sentAuth = true;
        sock.write(`auth ${token}\n`);
      }
      // Once OK appears twice (banner then auth), send the command.
      const okCount = (out.match(/\nOK\b/g) || []).length;
      if (okCount >= 1 && !sock._sentCmd) {
        sock._sentCmd = true;
        sock.write(`${cmd}\nquit\n`);
      }
      if (out.includes("Hello") === false && /\nOK\s*$/.test(out) && sock._sentCmd) {
        clearTimeout(timer);
        finish(true);
      }
    });
    sock.on("error", (e) => {
      clearTimeout(timer);
      finish(false, e.message);
    });
    sock.on("close", () => {
      clearTimeout(timer);
      // If we already sent the cmd and got at least one OK, treat as success.
      if (sock._sentCmd && /OK/.test(out)) finish(true);
      else finish(false, "closed");
    });
  });
}

export async function geoFix(lng, lat, alt) {
  const parts = [lng, lat];
  if (alt != null) parts.push(alt);
  return emuCommand(`geo fix ${parts.join(" ")}`);
}
