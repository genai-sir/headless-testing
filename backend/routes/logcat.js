// GET /api/logcat?tag=MyTag&lines=200 -> last N logcat lines, optionally filtered.
// GET /api/logcat/stream -> SSE stream of new lines as they arrive.

import { Router } from "express";
import { spawn } from "node:child_process";
import { config } from "../config.js";
import { adb } from "../lib/adb.js";

const router = Router();

function buildLogcatArgs({ tag, level = "V", lines }) {
  // -d dump-and-exit (for the snapshot endpoint)
  const args = [];
  if (config.adbSerial) args.unshift("-s", config.adbSerial);
  args.push("logcat");
  if (lines) args.push("-t", String(lines));
  if (tag) args.push(`${tag}:${level}`, "*:S");
  return args;
}

router.get("/", async (req, res) => {
  const { tag, level, lines = 200 } = req.query;
  const args = buildLogcatArgs({ tag, level, lines: Number(lines) || 200 });
  const r = await adb(args.slice(args.indexOf("logcat")), { timeoutMs: 10000 });
  res.json({
    ok: r.ok,
    lines: r.stdout ? r.stdout.split("\n") : [],
    stderr: r.stderr,
  });
});

router.get("/stream", (req, res) => {
  const { tag, level } = req.query;
  const args = [];
  if (config.adbSerial) args.push("-s", config.adbSerial);
  args.push("logcat", "-v", "time");
  if (tag) args.push(`${tag}:${level || "V"}`, "*:S");

  res.set({
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  res.flushHeaders();

  const proc = spawn(config.adbPath, args, { stdio: ["ignore", "pipe", "pipe"] });

  proc.stdout.on("data", (d) => {
    for (const line of d.toString().split("\n")) {
      if (line) res.write(`data: ${line}\n\n`);
    }
  });
  proc.stderr.on("data", (d) => res.write(`event: error\ndata: ${d.toString().trim()}\n\n`));
  proc.on("close", () => res.end());

  req.on("close", () => proc.kill("SIGTERM"));
});

export default router;
