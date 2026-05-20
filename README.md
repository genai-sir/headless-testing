# headless-android

Browser-based rooted Android 14 with APK sideloading, GPS mocking, and root shell.

Two backends, same dashboard:

| Host | Engine | Root | Notes |
| --- | --- | --- | --- |
| macOS (Apple Silicon / Intel) | Android Studio AVD | `adb root` on `google_apis` AOSP image | Local dev. One device. |
| Linux server | Redroid (Docker) | Built into container image | Production. Multi-instance ready. Needs kernel binder/ashmem or KVM. |

The dashboard (Node/Express on `:3000`) talks ADB and embeds [ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) (`:8000`) for the live screen.

---

## Quickstart — macOS (AVD)

Prereqs (already detected on your machine, but verify with `scripts/doctor.sh`):
- Android SDK at `~/Library/Android/sdk` (sdkmanager, avdmanager, emulator, adb)
- Node 20+
- ~12 GB disk free (system image + AVD)

```bash
# one-time: install Android 14 system image + create rooted AVD
scripts/avd-up.sh

# this script also starts:
#   - emulator (headless-pixel AVD)
#   - ws-scrcpy   on http://localhost:8000
#   - backend     on http://localhost:3000  → open this
```

Stop everything: `scripts/avd-down.sh`

## Quickstart — Linux (Redroid Docker)

Prereqs on the Linux host:
- Docker + Docker Compose
- Kernel modules: `binder_linux`, `ashmem_linux` loaded (most distros need `redroid-modules` DKMS, see [redroid wiki](https://github.com/remote-android/redroid-doc))
- adb on the host

```bash
scripts/redroid-up.sh
# starts redroid + ws-scrcpy + backend via docker compose
# dashboard:  http://<host>:3000
# screen:     http://<host>:8000
```

Stop: `scripts/redroid-down.sh`

---

## What the dashboard does

- **Device panel** — boot/halt the emulator, see boot status, root status, Android version, IP, serial.
- **APK sideload** — drag-and-drop. Backend writes to `/tmp` then runs `adb install -r -g`.
- **Mock location** — lat/lng input + a few preset cities. Uses `adb emu geo fix` on AVD; on Redroid uses the bundled helper APK (see below).
- **Root shell** — issue commands as root. Pre-flighted with `adb root` if needed.
- **Logs** — tail `adb logcat` filtered by tag.

## Mock location notes

- **AVD**: Uses the emulator console (`adb emu geo fix LNG LAT`). Works out of the box.
- **Redroid**: Android's mock location requires an app registered as the mock provider. The dashboard installs `mock-location-helper/MockLocationHelper.apk` on first boot, grants it `android:mock_location` via `appops`, and sends coordinates via `am broadcast`. See [mock-location-helper/README.md](mock-location-helper/README.md) for the source.

## Layout

```
backend/   Node/Express API
web/       Static dashboard (served by backend)
scripts/   avd-up, avd-down, redroid-up, redroid-down, doctor
docker/    Compose + Dockerfiles for the Linux path
mock-location-helper/  Tiny APK + build notes
```

## Security

Single-user local tool. The dashboard exposes a root shell and runs commands as the emulator's root user. **Do not bind the backend to a public interface without putting it behind auth and TLS.** Default bind is `127.0.0.1:3000`.
