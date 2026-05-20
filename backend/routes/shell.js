import { Router } from "express";
import { runShell } from "../lib/device.js";

const router = Router();

router.post("/", async (req, res) => {
  const { cmd } = req.body || {};
  if (typeof cmd !== "string" || !cmd.trim()) {
    return res.status(400).json({ ok: false, error: "cmd required" });
  }
  const r = await runShell(cmd);
  res.json({
    ok: r.ok,
    code: r.code,
    stdout: r.stdout,
    stderr: r.stderr,
    timedOut: r.timedOut,
  });
});

export default router;
