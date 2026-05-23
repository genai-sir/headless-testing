# Stealth threat model

Concrete statement of what this stack hides from app-side detection, what it
does NOT hide, and what's out of scope. Keep this in sync with what
`mock-location-helper` actually hooks; if the hooks change, this doc should
change in the same commit.

## In scope (we hide these)

| Surface | How |
|---|---|
| `Location.isFromMockProvider()` returning `true` for system-provider Locations | Hook returns `false` when `provider ∈ {gps, network, fused, passive}` |
| `Location.isMock()` (API 31+), same condition | Same hook strategy |
| `Location.getExtras()` containing `mockLocation=true` for system-provider Locations | Hook removes the key before returning the Bundle |
| `Settings.Secure.getString(ALLOW_MOCK_LOCATION)` returning anything other than `"0"` | Hook returns `"0"` (legacy setting; always 0 on modern Android anyway) |
| `PackageManager.getInstalledPackages()` including `com.headless.mockloc` | Hook filters our own package out |
| `AppOpsManager` enumeration finding apps with `OPSTR_MOCK_LOCATION` granted | Same package-filter as above |
| Detector apps doing a behavioral self-test (`new Location("mock"); setMock(true); read isMock`) | Hooks gated on `provider in SYSTEM_PROVIDERS` — synthetic Locations pass through unchanged |

Validated against `io.github.auag0.mocklocationdetector` v2.0.0. All six
checks report green when the helper module is loaded and scoped.

## Out of scope (we do NOT hide these)

| Surface | Why |
|---|---|
| Play Integrity / SafetyNet attestation | Hardware-backed attestation runs in TEE on the device's keymaster. No userspace hook can fake it. Apps that gate on `MEETS_DEVICE_INTEGRITY` will fail. |
| Native code reading `/proc/*` or `/sys/*` | Our hooks are Java-level (XposedBridge). Native reads bypass them entirely. Apps that resolve location via JNI directly are not covered. |
| Behavioral / cross-sensor signals | Accelerometer + gyro suggest the device is stationary while reported GPS moves at 80 km/h → app can flag mock without ever calling `isMock()`. Out of scope. |
| Network-side fingerprinting | Source IP doesn't match claimed location, ASN suggests datacenter, no carrier IPs, etc. Mitigations live at the network layer, not in this module. |
| Magisk presence detection | Magisk Manager package (`com.topjohnwu.magisk`) is visible to `pm list packages` by default. LSPosed Manager (`org.lsposed.manager`) too. Apps that grep for these will succeed. |
| Zygisk denylist evasion | We enable Zygisk to load LSPosed but don't configure Magisk's denylist for individual target apps. |
| Time / timezone mismatch | `TimeZone.getDefault()` is not hooked. If the spoofed coordinate is in Asia and the device timezone is America/Los_Angeles, that's a tell. |

## Known operational gaps

1. **Fork drift.** Magisk Delta (HuskyDG fork v30.6), LSPosed-Zygisk (JingMatrix
   v1.11), MindTheGApps (s1204IT). All third-party forks. Upstream Magisk
   doesn't ship Magisk Delta builds; LSPosed has multiple competing forks
   ("Vector" is current at JingMatrix). Plan for periodic drift checks.

2. **Custom redroid image only exists locally.** Until `scripts/push-redroid-image.sh`
   ships and the image is pinned by sha256 digest, every VM rebuild re-bakes
   from scratch — the bake script is reproducible but the result is not pinned.

3. **No HSM / hardware attestation.** A real device's keymaster is rooted in
   silicon; redroid's is software. Any caller that demands hardware-backed
   keys for location proofs will fail.

4. **LSPosed Manager is exposed.** `org.lsposed.manager` is in the package
   list and visible in launchers. Apps that allowlist-fail on "LSPosed
   installed" will catch us. Consider hiding it via Magisk's denylist or via
   the helper module's `PackageManagerHooks` (currently scoped to
   `com.headless.mockloc` only).

5. **Single redroid instance.** No multi-tenancy. Multiple test scenarios
   on the same VM would interfere via shared `/data/adb/lspd/config/`.

## What to test when changing hooks

Before merging any change to `mock-location-helper`:

- [ ] `io.github.auag0.mocklocationdetector` v2.0.0 still reports six green dots.
- [ ] `/api/health` returns 200 after a clean reboot.
- [ ] At least one app using `LocationManager.requestLocationUpdates(GPS_PROVIDER, ...)`
      sees `isFromMockProvider() == false` for a location pushed via
      `com.headless.mockloc.SET_LOCATION` broadcast.
- [ ] LSPosed Manager loads (its `Modules` tab is non-blank).

## Escalation surface

If a new detector flags us, the iteration loop is:

1. Pull the detector APK; `jadx` it; find the exact check.
2. Decide: gate an existing hook on more context, or add a new targeted hook.
3. `mock-location-helper/gradlew assembleDebug`, install, re-test.
4. Commit the new hook with a one-line `// against <detector pkg> v<version>` note.

The PR template should include the detector name + version it was validated against.
