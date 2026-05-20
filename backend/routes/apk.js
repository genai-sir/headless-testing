import { Router } from "express";
import multer from "multer";
import { mkdirSync } from "node:fs";
import { unlink } from "node:fs/promises";
import { join } from "node:path";
import { config } from "../config.js";
import { installApk } from "../lib/device.js";

mkdirSync(config.uploadsDir, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: config.uploadsDir,
    filename: (_req, file, cb) => {
      const safe = file.originalname.replace(/[^A-Za-z0-9._-]+/g, "_");
      cb(null, `${Date.now()}_${safe}`);
    },
  }),
  limits: { fileSize: 500 * 1024 * 1024 }, // 500 MB
  fileFilter: (_req, file, cb) => {
    if (!/\.apk$/i.test(file.originalname)) {
      return cb(new Error("only .apk files accepted"));
    }
    cb(null, true);
  },
});

const router = Router();

router.post("/", upload.single("apk"), async (req, res) => {
  if (!req.file) return res.status(400).json({ ok: false, error: "no file" });
  const path = join(config.uploadsDir, req.file.filename);
  try {
    const result = await installApk(path);
    res.json({
      ok: result.ok,
      file: req.file.originalname,
      size: req.file.size,
      install: result,
    });
  } finally {
    unlink(path).catch(() => {});
  }
});

export default router;
