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

## Synology NAS (DS224+ / Intel-based)

Tested on DS224+ (Celeron J4125, 10 GB RAM, DSM 7.x). Any Intel-based Synology with Container Manager should work.

### Prerequisites

1. **Container Manager** installed from DSM Package Center.
2. **SSH enabled**: Control Panel → Terminal & SNMP → Enable SSH service.

### Deploy

From your Mac (or any machine), copy the project to the NAS and run the deploy script:

```bash
# copy the project to the NAS (replace NAS_IP)
rsync -avz --exclude node_modules --exclude .git \
  . admin@NAS_IP:/volume1/docker/headless-android/

# SSH in and deploy
ssh admin@NAS_IP
cd /volume1/docker/headless-android
sudo bash scripts/synology-deploy.sh
```

The script will:
1. Check if `binder_linux` / `ashmem_linux` kernel modules are available
2. If not, **automatically compile them** from Synology's GPL kernel source via Docker (~500 MB download, 10-20 min first time only)
3. Load the modules and create a boot script so they survive NAS reboots
4. Build and start all three containers (redroid, ws-scrcpy, backend)
5. Print the LAN URLs when done

If the auto-build fails (vermagic mismatch), rebuild with your exact DSM build number:

```bash
# find your DSM build number
cat /etc.defaults/VERSION

# rebuild targeting that exact version
DSM_BUILD=7.2-72806 sudo bash scripts/synology-build-modules.sh
sudo bash scripts/synology-deploy.sh
```

### Access from your network

```
Dashboard:  http://<NAS_IP>:3000
Screen:     http://<NAS_IP>:8000
adb:        adb connect <NAS_IP>:5555
```

The dashboard auto-resolves ws-scrcpy's URL to the NAS IP when accessed over the network — no manual config needed.

### Lower resource usage (optional)

On a Celeron J4125, you can reduce the Android display to save CPU:

```bash
# in the project directory on the NAS
REDROID_FPS=30 REDROID_HEIGHT=1280 REDROID_WIDTH=720 \
  sudo docker compose -f docker/docker-compose.yml up -d --build
```

### Stop / restart

```bash
# stop
sudo docker compose -f /volume1/docker/headless-android/docker/docker-compose.yml down

# restart
sudo docker compose -f /volume1/docker/headless-android/docker/docker-compose.yml up -d
```

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

## Stealth (hide mock GPS from apps)

```bash
# one-shot: Magisk + LSPosed + stealth module + DB enable + reboots
scripts/install-magisk-avd.sh

# scope-enable the module on each target app
scripts/scope.sh add com.uber.app
scripts/scope.sh add com.your.bank.app
scripts/scope.sh apply              # reboot so hooks load
scripts/scope.sh list               # what's currently scoped
```

The dashboard's **Stealth** panel shows live status of all four layers
(Magisk / LSPosed / stealth APK / mock_location appop). When all four are
green and the target app is in scope, the app sees `Location.isFromMockProvider()
= false` and our helper package isn't visible in its PackageManager.

See [mock-location-helper/README.md](mock-location-helper/README.md) for the
full detection-vs-defeat matrix.

## Layout

```
backend/   Node/Express API
web/       Static dashboard (served by backend)
scripts/   avd-up, avd-down, redroid-up, redroid-down, doctor,
           install-magisk-avd (stealth bootstrap), scope (per-app scope)
docker/    Compose + Dockerfiles for the Linux path
mock-location-helper/  LSPosed module + plain BroadcastReceiver in one APK
```

## Security

Single-user local tool. The dashboard exposes a root shell and runs commands as the emulator's root user. **Do not bind the backend to a public interface without putting it behind auth and TLS.** Default bind is `127.0.0.1:3000`.
