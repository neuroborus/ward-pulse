# Phone-to-Watch Acceptance

This tool prepares and verifies the paired-emulator path used by WardPulse Phase 5.
It belongs under `tools/` rather than either app's test sources because it orchestrates
Flutter, Gradle, Android SDK packages, two AVDs, and ADB.

## Prerequisites

- `ANDROID_HOME` points to the Android SDK.
- Flutter is on `PATH`, or `WARDPULSE_FLUTTER_BIN` points to its executable.
- Android Studio is available for the Wear OS pairing assistant.
- The canonical round Wear AVD exists.

Prepare the Play Store phone image and AVD once:

```sh
just prepare-phone-watch-sync
```

Start `wardpulse_phone_play_api36` and `wardpulse_wear_round_api36_1`, pair them in Android
Studio, and install the Google Pixel Watch companion with a dedicated test Google account.
The companion's optional `Associate` action is not part of this acceptance flow and is not
required for Data Layer.

Run the acceptance check:

```sh
just test-phone-watch-sync
```

The check runs the Wear device tests, installs both apps, waits for the redacted Wear receipt
log, and verifies that the saved summary survives a phone app force-stop and Wear app restart
unchanged. When more than one phone or Wear device is online, select them explicitly:

```sh
PHONE_SERIAL=emulator-5554 \
WEAR_SERIAL=emulator-5556 \
just test-phone-watch-sync
```
