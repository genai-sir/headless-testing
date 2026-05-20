import { Router } from "express";
import { deviceInfo, ensureRoot } from "../lib/device.js";

const router = Router();

router.get("/", async (_req, res) => {
  res.json(await deviceInfo());
});

router.post("/root", async (_req, res) => {
  const ok = await ensureRoot();
  res.json({ ok, rooted: ok });
});

export default router;
