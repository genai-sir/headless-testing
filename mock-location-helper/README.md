# mock-location-helper / stealth module

One APK, two jobs:

| Without LSPosed | With LSPosed |
| --- | --- |
| BroadcastReceiver that registers test providers and applies coordinates. | Same receiver **plus** Xposed hooks that hide the mock from apps. |

Used by the **Redroid** backend always, and by the **AVD** backend whenever
stealth is desired (otherwise `adb emu geo fix` is enough — but apps will see
`isFromMockProvider=true`).

## What the hooks do

Inside every target app process that LSPosed loads the module into:

| Hook | Effect |
| --- | --- |
| `Location.isFromMockProvider()` | always returns `false` |
| `Location.isMock()` (API 31+) | always returns `false` |
| `Location.getExtras()` | strips legacy `mockLocation` key |
| `Settings.Secure.getInt("mock_location", …)` | returns `0` |
| `Settings.Secure.getString("mock_location")` | returns `"0"` |
| `PackageManager.getInstalledPackages/Applications` | filters out `com.headless.mockloc` |
| `PackageManager.queryIntent{Activities,Services,Receivers}` | same |
| `PackageManager.get{Package,Application}Info("com.headless.mockloc", …)` | throws `NameNotFoundException` |

What this **does not** defeat (out of scope for the "quick win" build):

- GNSS satellite-status checks (`GnssStatus.Callback`, `GnssMeasurementsEvent`)
- Play Integrity / SafetyNet attestation
- Emulator fingerprint checks (`ro.kernel.qemu`, `Build.HARDWARE`, missing sensors)
- Apps that probe via root cloak (Magisk-DenyList / Shamiko cover these separately)

So: rideshare, dating, delivery, social, most banking → defeated. Pokémon Go,
Play-Integrity-gated apps → not defeated by this module alone.

## Build

JDK 17 + Gradle. The wrapper isn't checked in; bootstrap with global Gradle once:

```bash
cd mock-location-helper
gradle wrapper                    # one-time, creates ./gradlew
./gradlew assembleDebug
# APK lands at:
#   app/build/outputs/apk/debug/app-debug.apk
```

## Install

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell cmd appops set com.headless.mockloc android:mock_location allow
```

For the Xposed bits to activate you must additionally:

1. Have **Magisk + LSPosed (Zygisk)** installed in the device.
   - AVD: `scripts/install-magisk-avd.sh` (uses rootAVD).
   - Redroid: use a Magisk-baked image such as `ayasa520/magisk-redroid`, or
     install Magisk manually via `magiskboot` + the boot image extracted from
     `/data/redroid`.
2. Open **LSPosed Manager** → Modules → enable "headless-android stealth".
3. In the same screen, set **Scope** to include every app that should see
   the location as non-mock (Uber, Tinder, your target apps).
4. Reboot the device once (`adb reboot`).

## Send a coordinate

The dashboard's "set location" button does this for you on the Redroid backend;
for manual use:

```bash
adb shell am broadcast \
  -a com.headless.mockloc.SET_LOCATION \
  -n com.headless.mockloc/.LocationReceiver \
  --ef lat 37.7749 --ef lng -122.4194

# stop mocking
adb shell am broadcast \
  -a com.headless.mockloc.STOP \
  -n com.headless.mockloc/.LocationReceiver
```

## Verify the hook is live

A scope-enabled app will see no mock flag. Quick test:

```bash
# from an scrcpy session, launch any "GPS Status" / "GPS Test" app of your choice
# and check whether it reports the location as 'mock'.
# Or use a one-line check from an instrumented test:
#   Location l = lm.getLastKnownLocation(GPS_PROVIDER);
#   l.isFromMockProvider();   // -> false  (with hook)
```

LSPosed Manager → Logs tab will also show:
```
[headless-stealth] LocationHooks installed in <pkg>
```
when verbose logging is enabled.
