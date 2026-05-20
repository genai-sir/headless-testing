# MockLocationHelper

Tiny APK that registers test providers (GPS, NETWORK, FUSED) and applies coordinates
sent over a broadcast.

- Used by the **Redroid** backend, where `adb emu geo fix` is unavailable.
- Not needed for the **AVD** backend.

## Build

Requires a JDK 17 and either the Gradle wrapper (run `gradle wrapper` once if
the wrapper jar isn't checked in) or a global Gradle.

```bash
cd mock-location-helper
gradle assembleDebug      # or: ./gradlew assembleDebug
# APK lands at:
#   app/build/outputs/apk/debug/app-debug.apk
```

Then the install/permission grant (the dashboard does this automatically; commands
shown here for manual use):

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell cmd appops set com.headless.mockloc android:mock_location allow
```

## Manual use

```bash
# San Francisco
adb shell am broadcast \
  -a com.headless.mockloc.SET_LOCATION \
  -n com.headless.mockloc/.LocationReceiver \
  --ef lat 37.7749 --ef lng -122.4194

# stop mocking
adb shell am broadcast \
  -a com.headless.mockloc.STOP \
  -n com.headless.mockloc/.LocationReceiver
```

## Wiring

`backend/lib/location.js` formats the same broadcast — when the dashboard's
"set location" button is clicked on Redroid, the backend:

1. `adb shell cmd appops set com.headless.mockloc android:mock_location allow`
2. `adb shell am broadcast -a ... --ef lat ... --ef lng ...`

The receiver applies the coordinates to all three providers so any client API
(`LocationManager`, fused location, etc.) sees them.
