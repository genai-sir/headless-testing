import { Router } from "express";
import { setLocation } from "../lib/location.js";

const router = Router();

router.post("/", async (req, res) => {
  const { lat, lng, alt, accuracy } = req.body || {};
  const fLat = Number(lat);
  const fLng = Number(lng);
  if (!Number.isFinite(fLat) || !Number.isFinite(fLng)) {
    return res.status(400).json({ ok: false, error: "lat and lng required" });
  }
  if (fLat < -90 || fLat > 90 || fLng < -180 || fLng > 180) {
    return res.status(400).json({ ok: false, error: "lat/lng out of range" });
  }
  const result = await setLocation({
    lat: fLat,
    lng: fLng,
    alt: alt == null ? undefined : Number(alt),
    accuracy: accuracy == null ? undefined : Number(accuracy),
  });
  res.json(result);
});

export default router;
