import "dotenv/config";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

function detectAdb() {
  if (process.env.ADB_PATH) return process.env.ADB_PATH;
  const candidates = [
    join(homedir(), "Library/Android/sdk/platform-tools/adb"),
    "/usr/local/bin/adb",
    "/opt/homebrew/bin/adb",
    "/usr/bin/adb",
  ];
  for (const c of candidates) if (existsSync(c)) return c;
  return "adb";
}

function detectBackendType() {
  if (process.env.BACKEND_TYPE) return process.env.BACKEND_TYPE;
  if (process.env.ADB_SERIAL?.startsWith("127.0.0.1:5555")) return "redroid";
  return process.platform === "darwin" ? "avd" : "redroid";
}

export const config = {
  host: process.env.HOST || "127.0.0.1",
  port: Number(process.env.PORT) || 3000,
  wsScrcpyUrl: process.env.WS_SCRCPY_URL || "http://localhost:8000",
  adbPath: detectAdb(),
  adbSerial: process.env.ADB_SERIAL || "",
  backendType: detectBackendType(),
  emulatorAuthTokenPath:
    process.env.EMULATOR_AUTH_TOKEN_PATH ||
    join(homedir(), ".emulator_console_auth_token"),
  uploadsDir: join(process.cwd(), "uploads"),
  // MITM (traffic monitoring) settings.
  // mitm.apiUrl is the URL of mitmweb as seen *from the backend container*.
  // mitm.proxyHost/Port is the proxy as seen *from redroid* (set on the
  // device's global http_proxy).
  mitm: {
    // Where mitmweb listens. mitmproxy joins redroid's netns so this address
    // resolves to the redroid service in the docker network.
    apiUrl: process.env.MITM_API_URL || "http://redroid:8081",
    webPassword: process.env.MITM_WEB_PASSWORD || "headless-mitm",
  },
};
