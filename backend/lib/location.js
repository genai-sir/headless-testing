// Mock location dispatcher.
//   AVD     -> emulator console "geo fix"
//   Redroid -> broadcast to bundled MockLocationHelper (com.headless.mockloc)

import { geoFix } from "./emu.js";
import { adb, shell } from "./adb.js";
import { config } from "../config.js";

const HELPER_PKG = "com.headless.mockloc";
const HELPER_ACTION = `${HELPER_PKG}.SET_LOCATION`;
const HELPER_RECEIVER = `${HELPER_PKG}/.LocationReceiver`;

export async function setLocationAvd({ lat, lng, alt }) {
  // emulator console expects "longitude latitude [altitude]"
  return geoFix(lng, lat, alt);
}

export async function ensureMockLocationAllowed() {
  // Grant the helper app the mock-location appop (root required, both
  // Redroid and a rooted AVD have it).
  await shell(`cmd appops set ${HELPER_PKG} android:mock_location allow`);
}

export async function setLocationRedroid({ lat, lng, alt = 0, accuracy = 5 }) {
  await ensureMockLocationAllowed();
  const extras = [
    "--ef", "lat", String(lat),
    "--ef", "lng", String(lng),
    "--ef", "alt", String(alt),
    "--ef", "accuracy", String(accuracy),
  ];
  const r = await adb([
    "shell",
    "am", "broadcast",
    "-a", HELPER_ACTION,
    "-n", HELPER_RECEIVER,
    ...extras,
  ]);
  return {
    ok: r.ok && /Broadcast completed: result=0/.test(r.stdout),
    output: r.stdout,
    error: r.stderr,
  };
}

export async function setLocation(coords) {
  if (config.backendType === "avd") {
    const r = await setLocationAvd(coords);
    return { ok: r.ok, via: "emu geo fix", detail: r };
  }
  const r = await setLocationRedroid(coords);
  return { ok: r.ok, via: "MockLocationHelper broadcast", detail: r };
}
