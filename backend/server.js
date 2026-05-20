import express from "express";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { config } from "./config.js";
import deviceRoutes from "./routes/device.js";
import apkRoutes from "./routes/apk.js";
import locationRoutes from "./routes/location.js";
import shellRoutes from "./routes/shell.js";
import logcatRoutes from "./routes/logcat.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webDir = join(__dirname, "..", "web");

const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/api/config", (_req, res) => {
  res.json({
    backendType: config.backendType,
    wsScrcpyUrl: config.wsScrcpyUrl,
    adbSerial: config.adbSerial || null,
  });
});

app.use("/api/device", deviceRoutes);
app.use("/api/apk", apkRoutes);
app.use("/api/location", locationRoutes);
app.use("/api/shell", shellRoutes);
app.use("/api/logcat", logcatRoutes);

// Serve the dashboard static files.
app.use(express.static(webDir));

app.use((err, _req, res, _next) => {
  console.error("API error:", err);
  res.status(500).json({ ok: false, error: err.message || String(err) });
});

app.listen(config.port, config.host, () => {
  console.log(
    `headless-android backend listening on http://${config.host}:${config.port}`
  );
  console.log(`  backend type: ${config.backendType}`);
  console.log(`  adb:          ${config.adbPath}${config.adbSerial ? " -s " + config.adbSerial : ""}`);
  console.log(`  ws-scrcpy:    ${config.wsScrcpyUrl}`);
});
