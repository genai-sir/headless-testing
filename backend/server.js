import express from "express";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { config } from "./config.js";
import deviceRoutes from "./routes/device.js";
import apkRoutes from "./routes/apk.js";
import locationRoutes from "./routes/location.js";
import shellRoutes from "./routes/shell.js";
import logcatRoutes from "./routes/logcat.js";
import stealthRoutes from "./routes/stealth.js";
import scopeRoutes from "./routes/scope.js";
import healthRoutes from "./routes/health.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webDir = join(__dirname, "..", "web");

const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/api/config", (req, res) => {
  // When accessed over the network, rewrite localhost in wsScrcpyUrl to the
  // actual host the browser used so the iframe reaches the NAS, not the laptop.
  let wsUrl = config.wsScrcpyUrl;
  const reqHost = req.hostname;
  if (reqHost && reqHost !== "localhost" && reqHost !== "127.0.0.1") {
    wsUrl = wsUrl.replace(/\blocalhost\b|127\.0\.0\.1/, reqHost);
  }
  res.json({
    backendType: config.backendType,
    wsScrcpyUrl: wsUrl,
    adbSerial: config.adbSerial || null,
  });
});

app.use("/api/device", deviceRoutes);
app.use("/api/apk", apkRoutes);
app.use("/api/location", locationRoutes);
app.use("/api/shell", shellRoutes);
app.use("/api/logcat", logcatRoutes);
app.use("/api/stealth", stealthRoutes);
app.use("/api/scope", scopeRoutes);
app.use("/api/health", healthRoutes);

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
