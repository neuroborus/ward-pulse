# Android Toolchain

This document is the operational source of truth for the WardPulse Android development
environment. It records the baseline through the Phase 7 implementation, canonical SDK
package names, local paths, verification commands, and tooling that is intentionally not
installed yet.

Last verified: **2026-07-19** on TUXEDO OS 24.04.4 LTS, x86_64.

## Current Readiness

The command-line toolchain required through the local **Phase 7 — first real provider**
build and test gates is ready:

- Flutter detects the Android SDK and reports the Android toolchain as healthy.
- All Android SDK licenses are accepted.
- Android 16 / API 36 and Build Tools 36.0.0 are installed.
- Android SDK Platform 35 is installed for Flutter plugin builds that declare that compile SDK.
- The canonical phone AVD is installed, starts, and is detected by Flutter.
- `flutter analyze` passes for `apps/phone_flutter`.
- `flutter test` passes, including usage-history rendering and provider-detail navigation.
- `flutter build apk --debug` produces the WardPulse debug APK.
- The `app.wardpulse` runner starts on the canonical AVD and renders the dashboard,
  usage-history chart, provider list, and provider detail screen.
- `cargo-ndk 4.1.2` and the Android Rust targets for `arm64-v8a` and `x86_64` are installed.
- The Rust library builds with Android NDK r29 and is packaged into the Flutter APK for
  both supported ABIs.
- The phone app loads the golden dashboard snapshot from Rust at runtime and maps bridge
  failures to the safe unavailable state.
- The phone debug APK includes platform-secure OpenAI credential storage and the live
  reporting FFI boundary; it starts successfully on the canonical AVD.
- Android SDK Platform 37.1 is installed for the Wear compile SDK while target SDK remains
  API 36.
- The Wear OS 6.1 x86_64 system image and canonical round and square AVDs are installed.
- The Wear app passes lint, builds its debug and instrumentation APKs, runs on both AVD
  shapes, and passes its local-persistence tests on the round AVD.
- Phone and Wear builds use Wearable Data Layer `20.0.1`; the Wear listener validates the
  versioned summary before replacing locally persisted state.
- Historical paired-device acceptance on 2026-07-19 delivered the canonical summary and
  retained it after phone force-stop and Wear restart. That result does not establish
  current process, publication or scheduled-work preservation; the current gate requires
  the complete checks in Routine Verification below.
- The official WFF validator accepts the declarative watch face, and the package builds as
  APK/AAB without dex files.
- The watch face installs and renders on the round and square Wear AVDs; tap-to-open and
  ambient mode pass emulator acceptance (ambient is entered with `KEYCODE_SLEEP` — see Wear
  emulator navigation).

The Phase 2 phone-dashboard, Phase 3 Rust-bridge, and Phase 4 Wear-app acceptance gates
passed on **2026-07-18**. Phase 5 paired-device and Phase 6 WFF acceptance passed on
**2026-07-19**. The face was checked on the square AVD, and ambient on both shapes, on
**2026-08-12**.

Chrome and Linux desktop warnings from `flutter doctor` are out of scope. WardPulse targets
Android phone, Wear OS, and Watch Face Format in the current product plan.

## Verified Versions

| Component | Verified version | Current role |
| --- | --- | --- |
| Flutter | 3.44.6, stable channel | Phase 2 phone UI |
| Dart | 3.12.2, bundled with Flutter | Phase 2 phone UI |
| Flutter DevTools | 2.57.0 | Flutter diagnostics |
| OpenJDK / `javac` | 21.0.11 | Android builds and SDK tools |
| Android Studio | Quail 2, 2026.1.2 | Wear emulator pairing and Android project tooling |
| Android CLI | 1.0.15857036 | SDK package management and Android tooling |
| Android SDK Command-line Tools | 22.0 | `android`, `avdmanager`, and bootstrap SDK tools |
| Android SDK Platform | `platforms;android-35`, revision 2 | Flutter plugin compile compatibility |
| Android SDK Platform | `platforms;android-36`, revision 2 | Compile SDK baseline |
| Android SDK Platform | `platforms;android-37.1`, revision 1 | Wear compile SDK |
| Android SDK Build Tools | `build-tools;36.0.0` | Android build baseline |
| Android SDK Platform Tools | 37.0.0 | `adb` |
| Android Emulator | 36.6.11.0, build 15507667 | Phone emulator |
| Android phone system image | `system-images;android-36;google_apis_playstore;x86_64`, revision 7 | Phone AVD (Play Store) |
| Android Wear system image | `system-images;android-36.1;android-wear-signed;x86_64`, revision 1 | Wear OS 6.1 AVDs |
| Gradle Wrapper | 9.1.0 | Flutter Android build |
| Android Gradle Plugin | 9.0.1 | Flutter Android runner |
| Kotlin Gradle Plugin | 2.3.20 | Flutter Android host activity |
| Wear Gradle Wrapper | 9.6.1 | Native Wear app build |
| Wear Android Gradle Plugin | 9.3.0 | Native Wear app build |
| WFF validator | 1.7.0 | WFF v2 schema validation |
| Wear Kotlin Compose plugin | 2.3.21 | Compose compiler; Kotlin compilation is built into AGP |
| Compose BOM | 2026.06.00 | Wear Compose runtime baseline |
| Compose for Wear OS | 1.6.2 | Material 3 UI and preview tooling |
| AndroidX Activity | 1.13.0 | Wear Compose activity host |
| AndroidX Core | 1.19.0 | Android Kotlin extensions |
| Google Play services Wearable | 20.0.1 | Phone-to-watch Data Layer transport |
| Android NDK | `ndk;28.2.13676358` | Flutter Android debug build |
| Android NDK | `ndk;29.0.14206865` | Rust Android library builds |
| Android SDK CMake | 3.22.1 | Flutter Android debug build |
| Host CMake | 3.31.6 | Available for later native build work |
| Rust | 1.96.0 | Domain core and Android library builds |
| Cargo | 1.96.0 | Rust workspace |
| cargo-ndk | 4.1.2 | Rust builds for Android ABIs |
| Rust Android targets | `aarch64-linux-android`, `x86_64-linux-android` | Phone device and emulator libraries |
| Dart `ffi` package | 2.2.0 | UTF-8 C ABI wrapper |
| Flutter Secure Storage | 10.3.1 | Android credential encryption |
| URL Launcher | 6.3.2 | External OpenAI device-code sign-in page |
| Node.js | 24.x | Documentation and design tooling |
| Git | 2.43.0 | Source control and Flutter SDK support |

The Rust workspace declares Rust 1.75 as its minimum supported version. The newer local
toolchain must continue to pass the minimum-version CI job.

## Canonical Names And Paths

Use these names consistently in local commands and future automation:

```text
Flutter SDK:       $HOME/develop/flutter
Android SDK:       $HOME/Android/Sdk
Android Studio:    $HOME/.local/opt/android-studio
Java home:         /usr/lib/jvm/java-21-openjdk-amd64
Phone AVD:         wardpulse_phone_play_api36
Phone platform:    android-36
Phone system image system-images;android-36;google_apis_playstore;x86_64
Wear compile SDK:  platforms;android-37.1
Wear system image: system-images;android-36.1;android-wear-signed;x86_64
Wear round AVD:    wardpulse_wear_round_api36_1
Wear square AVD:   wardpulse_wear_square_api36_1
Application ID:    app.wardpulse
Wear namespace:    app.wardpulse.wear
Watch face ID:      app.wardpulse.watchface
Flutter NDK:       ndk;28.2.13676358
Rust bridge NDK:   ndk;29.0.14206865
cargo-ndk:         4.1.2
Phone Rust ABIs:   arm64-v8a, x86_64
Rust targets:      aarch64-linux-android, x86_64-linux-android
```

The shell environment belongs in `~/.profile` as single-line exports:

```sh
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/develop/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

Apply profile changes to an existing shell with:

```sh
. "$HOME/.profile"
hash -r
```

Do not install a separate Dart SDK. Use the Dart version bundled with Flutter. Do not install
a global Gradle distribution for project builds; use the committed wrapper in each Android
project.

## Reproducible Android Installation

### Host packages and KVM

On Ubuntu 24.04 or TUXEDO OS 24.04:

```sh
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa cpu-checker qemu-system-x86
sudo modprobe kvm
sudo modprobe kvm_intel
sudo usermod -aG kvm "$(id -un)"
```

Log out and back in after changing KVM group membership, then verify:

```sh
id
kvm-ok
```

For AMD hosts, load `kvm_amd` instead of `kvm_intel`.

### Flutter

The pinned Phase 2 archive and checksum are:

```sh
mkdir -p "$HOME/develop"
cd /tmp
curl -fLO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.6-stable.tar.xz
printf '%s  %s\n' \
  'a6320fd72e9a2690c08e2a6a70874a30cb120dee7c78f49d2c628bd7c9e20525' \
  'flutter_linux_3.44.6-stable.tar.xz' \
  | sha256sum -c -
tar -xf flutter_linux_3.44.6-stable.tar.xz -C "$HOME/develop"
```

### Android Studio

Install the verified Linux archive per user and select the standard setup on first launch:

```sh
mkdir -p "$HOME/.local/opt"
tar -xzf /path/to/android-studio-quail2-linux.tar.gz -C "$HOME/.local/opt"
"$HOME/.local/opt/android-studio/bin/studio"
```

Use `$ANDROID_HOME` as the Android SDK location. A system-wide package is not required.

### Android command-line tools

```sh
export ANDROID_HOME="$HOME/Android/Sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"
cd /tmp
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip
printf '%s  %s\n' \
  '04453066b540409d975c676d781da1477479dde3761310f1a7eb92a1dfb15af7' \
  'commandlinetools-linux-14742923_latest.zip' \
  | sha256sum -c -
unzip -q commandlinetools-linux-14742923_latest.zip -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/20.0"

# The downloaded 20.0 bundle bootstraps the current tool package.
"$ANDROID_HOME/cmdline-tools/20.0/bin/sdkmanager" \
  --sdk_root="$ANDROID_HOME" \
  "cmdline-tools;latest"
```

Install the pinned phone, bridge, and Wear packages:

```sh
"$ANDROID_HOME/cmdline-tools/latest/bin/android" --sdk="$ANDROID_HOME" sdk install \
  platform-tools \
  platforms/android-35 \
  platforms/android-36 \
  platforms/android-37.1 \
  build-tools/36.0.0 \
  emulator \
  system-images/android-36/google_apis/x86_64 \
  system-images/android-36.1/android-wear-signed/x86_64 \
  ndk/28.2.13676358 \
  cmake/3.22.1 \
  ndk/29.0.14206865
```

Configure Flutter explicitly and populate Android artifacts:

```sh
flutter config --android-sdk "$ANDROID_HOME"
flutter precache --android
flutter doctor --android-licenses
```

### Rust Android bridge

Install the pinned targets and build helper:

```sh
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
```

Verify the installed bridge tooling:

```sh
cargo ndk --version
rustup target list --installed
```

## Phone AVD

Use **one** phone AVD with the Play Store image. It covers Flutter CLI work and Wear Data
Layer pairing (a second non-Play phone AVD only caused local confusion).

```sh
android --sdk="$ANDROID_HOME" sdk install \
  system-images/android-36/google_apis_playstore/x86_64

printf 'no\n' | avdmanager create avd \
  --name wardpulse_phone_play_api36 \
  --package "system-images;android-36;google_apis_playstore;x86_64" \
  --device pixel_7 \
  --force

# avdmanager may leave Play Store disabled. Set /data before the first boot.
sed -i \
  -e 's/^PlayStore.enabled=no$/PlayStore.enabled=yes/' \
  -e 's/^disk.dataPartition.size=.*$/disk.dataPartition.size=24G/' \
  "$HOME/.android/avd/wardpulse_phone_play_api36.avd/config.ini"
```

Set the size before starting the emulator: `/data` is materialized on first boot, and
`qemu-img resize` refuses to resize an AVD image that has snapshots. Treat the size as
immutable after that first boot; do not delete and recreate a configured canonical AVD merely
to change it. The storage-constrained single-ABI build guidance near `install-phone` can reduce
APK size, but does not replace sizing the AVD up front.

List and start it with:

```sh
emulator -list-avds
emulator -accel-check
emulator @wardpulse_phone_play_api36
```

Verify the running device from another shell:

```sh
adb devices -l
flutter devices
```

The expected Flutter device is an Android x64 emulator running Android 16 / API 36 with Play
Store. Start it together with one Wear AVD, then follow **Pairing the canonical phone and Wear
AVDs** below. The flow starts in Android Studio and completes companion consent through ADB.
Installing the Google Pixel Watch companion from Play Store requires a Google account on the
phone AVD; use a dedicated test account. The companion's optional `Associate` action is not
part of this acceptance flow and is not required for Data Layer. Both WardPulse APKs must use
application ID `app.wardpulse` and the same signing certificate; the Wear Kotlin namespace
remains `app.wardpulse.wear`.

## Wear OS AVDs

Create the canonical small round and square Wear OS 6.1 AVDs:

```sh
printf 'no\n' | avdmanager create avd \
  --name wardpulse_wear_round_api36_1 \
  --package "system-images;android-36.1;android-wear-signed;x86_64" \
  --device wearos_small_round \
  --force

printf 'no\n' | avdmanager create avd \
  --name wardpulse_wear_square_api36_1 \
  --package "system-images;android-36.1;android-wear-signed;x86_64" \
  --device wearos_square \
  --force
```

Run one Wear AVD at a time:

```sh
emulator @wardpulse_wear_round_api36_1
emulator @wardpulse_wear_square_api36_1
```

With either AVD active, build, test, install, and start the app:

```sh
just check-wear
just test-wear-device
just run-wear
```

### Wear emulator navigation

From the watch face, Android Emulator's **Button 1** opens the app launcher. If an app is
foregrounded, return home first. The equivalent deterministic ADB commands are:

```sh
adb -s "$WEAR_SERIAL" shell input keyevent 3
adb -s "$WEAR_SERIAL" shell input keyevent 264
```

Start WardPulse directly when launcher navigation is not under test:

```sh
adb -s "$WEAR_SERIAL" shell am start \
  -n app.wardpulse/app.wardpulse.wear.MainActivity
```

After `am start`, `keyevent 4` returns to the face — but send it once: from the face itself
both `4` and `3` open the launcher, and `4` from the launcher lands back on the face. When the
keys leave you stranded in the launcher, `am force-stop com.google.android.wearable.sysui`
restarts the system UI on the watch face.

To put a chosen summary on the face, write the app's prefs and then **start the app once**:

```sh
adb -s "$WEAR_SERIAL" push summary.xml /data/local/tmp/watch_summary.xml
adb -s "$WEAR_SERIAL" shell run-as app.wardpulse \
  cp /data/local/tmp/watch_summary.xml /data/data/app.wardpulse/shared_prefs/watch_summary.xml
adb -s "$WEAR_SERIAL" shell am start -n app.wardpulse/app.wardpulse.wear.MainActivity
```

The start is not optional: complications refresh only when something calls
`WatchComplicationUpdater.requestUpdate` (`MainActivity`, or the Data Layer listener). A prefs
file written behind the app's back leaves every slot showing its previous value, and the face
then measures exactly as it did before the change — which reads like a broken change rather
than a stale one.

Two more ways this misleads. After `pm clear` the app has no `shared_prefs/` directory at all,
so the `cp` above fails and the face falls back to `NoData` — arcs and strips vanish together,
which looks like a rendering bug rather than an empty payload; start the app once first so the
directory exists. And reinstalling the **face** package resets its slots the same way, so seed
after the install, not before.

**Controlled summary cases — debug Wear AVD only.** Verify the explicit ADB serial's canonical
AVD identity with `emu avd name` and use reviewed mock XML matching the actual summary schema.
Before replacement, preserve live bytes opaquely in a collision-free app-private device file
at mode 600; keep only hashes, original mode/UID and size on the host. Preserve the original
file's metadata (660 in the measured cases), not the backup's mode. Leave SharedPreferences
`.bak`/pending files untouched; do not erase them to force a quiet writer.

Record the actual peer and owned reverse mapping first. Airplane/Wi-Fi/Bluetooth switches did
not isolate the paired Round's ADB bridge: removing only its observed Wear `tcp:5601` reverse
and using [the existing connection refresh](#restarting-a-paired-emulator-set) proved that
peer disconnected. Restore that exact mapping and refresh to recover its original connection.
An unpaired Square with no reverse and no active peer must stay unpaired; do not create a
mapping or require a connected peer on cleanup. Leave phone forwarding, jobs, settings and
pairing alone. This route does not apply to physical devices.

Require a quiet writer and guards immediately before mutation; the pilot used three stable
summary hashes plus the intended disconnected peer. Late delivery, pending writes or changed
snapshot guards invalidate the case, not permission to overwrite newer live data. External
preference writes need a genuine cold load: prove the old PID retired, use `am start -W`, then
observe a nonempty new PID within a bound. An empty immediate `pidof` can be asynchronous
startup, not proof of cold load. An invisible previous app can remain in LAST/OOM adjustment
700 after ordinary `am kill`; in that observed state, opening existing Settings without
changes, returning Back and retrying `am kill` allowed retirement. Verify it; do not escalate
to force-stop, process signals, reset or data clear when that conditional route fails.

Use an outer `try/finally`-equivalent cleanup: a failed byte/PID reload must not bypass
restoration of recorded transport and touched OS/time state. Restore guarded original
bytes/metadata through a fresh process. Reconcile newer live delivery rather than clobbering it with the old
backup. Verify the original peer state and fresh whole Glance/Face after reload and settlement;
a copied file alone does not prove restoration. Remove only the operation's temporary file
after verified recovery; otherwise retain private recovery material and the unresolved result.

Ambient is `KEYCODE_SLEEP`, not the power button — `keyevent 26` leaves this image
interactive:

```sh
adb -s "$WEAR_SERIAL" shell input keyevent 223   # Dozing / DOZE_SUSPEND
adb -s "$WEAR_SERIAL" shell input keyevent 224   # back to interactive
```

`screencap` in doze captures the frame after the system's own dimming, which is neither a
scale nor a gamma of the interactive one. Use it to check that ambient renders what it should;
never read alpha levels off it.

**Controlled clock cases — Wear AVD only.** Never change a physical watch's or the Owner's
phone's clock for this route. Verify AVD identity before mutation; record host/watch epochs
and offset, `auto_time`, `auto_time_zone`, timezone ID, effective DND policy and renderer mode.
Arrange failure-safe cleanup first. Use existing `settings put global auto_time 0` and
`cmd alarm set-time TIME`, with epoch milliseconds for the intended local date/time in the
unchanged timezone. Do not replace live time with a Source change, mock or helper.

Bind each original to artifact/instance, actual clock and renderer mode before and after.
Sleep or `ambient=true` alone does not establish AMBIENT. For a chosen ambient minute,
establish the interactive case, position time shortly before the target minute, use the sleep
command above and bound observation around the actual minute tick/render. The measured
five-second pre-tick route worked where a 13-second wait from minute 00 did not establish
AMBIENT; neither duration is a universal timeout or completion receipt. Inspect a fresh
settled whole frame; metadata or a narrow glyph ROI cannot validate a mixed/overlay frame.

Check effective policy when a case requires normal INTERACTIVE/AMBIENT: a global `zen_mode`
write alone did not change Square's interruption filter. The supported
`cmd notification set_dnd off` route did; observe the effective filter and actual rendering.
Restore the original policy through its effective control, not just the setting bytes;
Square's original priority policy and MUTE renderer were valid restoration targets.

Always restore time from the current host epoch plus the saved watch offset, accounting for
elapsed time rather than replaying a frozen epoch; restore original automatic-time values,
unchanged timezone and touched effective DND policy. Verify actual clock, policy and original
renderer mode plus a fresh settled restored frame, even after a failed measurement. Missing
restoration proof remains unresolved. Record actual day/weather/UV and metric inputs per
frame: controlling time does not freeze them or certify a later candidate's fit.

**A blocking system view is separate from the face.** For the recurring GMS “Reset your
watch” view, temporary OS snooze of one exactly identified current notification was a bounded
visibility-only route, not a reset or notification erasure. Use it only when that identified
view blocks the authorized AVD case; retain the key privately and arrange unsnooze in outer
cleanup. `adb shell` joins arguments: preserve proper device-shell quoting of the entire key,
including pipes; host argument quoting alone is insufficient. Keep raw keys/payloads and
authentication out of logs. After unsnooze, verify that same notification's presence with a
fresh separate observation: an immediate false key-list result can be asynchronous. Do not
declare restoration or accept a covered frame from that first result alone.
Keep the private undo handle/recovery material until fresh recovery verification completes; a command return
or failed/ambiguous bounded check does not retire it. If exact identity is unavailable, report that limit
separately from independently proved effective manager-state recovery. Category/count evidence never
proves the exact notification's identity; keep these observations under [Diagnostic output privacy](#diagnostic-output-privacy).

Tap coordinates measured off a screenshot are a guess: the image is scaled, and a system dialog
sits above whatever it covers, so a near miss lands on the screen underneath and quietly changes
something else. Read the bounds instead, then tap their centre:

```sh
adb -s "$PHONE_SERIAL" shell uiautomator dump /sdcard/ui.xml
adb -s "$PHONE_SERIAL" shell cat /sdcard/ui.xml | tr '<' '\n' | grep -i "don.t allow"
# bounds="[133,1400][947,1547]" → tap 540 1473
```

The app compiles against Android SDK 37.1 but targets API 36 and runs on the Wear OS 6.1 /
API 36.1 image. Compile SDK and runtime system image versions are intentionally independent.

### Isolated Android Studio display

For work that exists only in Android Studio's desktop UI, run Studio on a separate nested
display. This leaves the owner's session, focus, pointer, and window layout untouched, but it
is not complete isolation — see the shared configuration note at the end of this section. The
following stack was verified on **2026-10-06**:

```sh
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 \
  Xwayland :7 -geometry 1280x800 -noreset &

DISPLAY=:7 WAYLAND_DISPLAY= XDG_RUNTIME_DIR=/run/user/1000 \
  KWIN_COMPOSE=N kwin_x11 --replace &

DISPLAY=:7 WAYLAND_DISPLAY= XDG_RUNTIME_DIR=/run/user/1000 \
  ~/.local/opt/android-studio/bin/studio &
```

Capture the complete nested desktop and send keyboard input with:

```sh
DISPLAY=:7 import -window root shot.png
DISPLAY=:7 xte 'key Tab' 'key Down' 'str Device Manager' 'key Return'
```

`KWIN_COMPOSE=N` is required. With composition enabled, `import -window root` captures an
empty frame; without it, windows draw directly into the root window and the capture contains
the whole desktop.

Pointer automation is unavailable in this rootful Xwayland stack. XTEST `mousemove` and
`mouseclick` events do not reach clients: hovering produces no pixel change, and clicking
opens no window. Keyboard XTEST works fully, so operate Studio entirely from the keyboard.

Keep the display at 1280×800. It fits the 560×448 pairing assistant, the 320×534 Device
Manager panel, and the 800×800 welcome window, while keeping screenshots readable at native
scale. A larger display only consumes more memory and forces captures to be scaled for review.
Set the geometry when Xwayland starts. Although
`xrandr --output XWAYLAND0 --mode 1280x800` changes the advertised size, root captures are
empty afterward; restart the display stack to change its geometry.

Emulators do not need this display. Continue to inspect and control them through ADB with an
explicit serial, using `exec-out screencap -p`, `input tap`, and `input keyevent`. When Studio
work is complete, stop the stack in reverse order: Studio, `kwin_x11`, then `Xwayland :7`.

`kwin_x11 --replace` shares configuration with the owner's account. It reads and writes the
same `~/.config/kwinrc` as the running session, and global key bindings belong to the
account-wide `kglobalaccel` service rather than to a display. On 2026-10-06
`~/.config/kglobalshortcutsrc` was rewritten while the nested compositor started; its bindings
were unchanged and each one was still registered to exactly one component. The nested display
therefore does not contain compositor configuration the way it contains focus and pointer
input. Confirm the owner's global shortcuts still fire after a session on it, and re-register
them with `systemctl --user restart plasma-kglobalaccel` rather than restarting the session.

### Diagnostic output privacy

Before service, window/task or environment inspection, identify the exact question and
allowlist the minimum facts needed. Project them before stdout/stderr reaches tool output,
logs, saved artifacts or another agent; never return raw sensitive service/environment data
for later redaction. Peer checks retain connection state, expected peer/role match and
required bridge-presence results. Compare necessary identities privately and retain match,
mismatch or unknown when their literals are unnecessary.

A whole matching line or broad search/context excerpt can include authentication or
push-registration data beside the intended fields. Do not echo full sensitive dumps,
raw profiles/environments, or such lines; do not retain them through tee or tracing.
Output limits, truncation and mode-600 files are not redaction. Missing, ambiguous or
unrecognized fields stay unavailable; do not widen the excerpt or guess a match.

Persist only the allowlisted facts. If an exposure occurs, stop reopening or copying its
output, restrict the owned saved artifact to a safe summary and report only the category
and containment performed. Do not recover/quote the credential or claim prior tool output
was erased. This rule authorizes no account, credential or pairing changes.

### Pairing the canonical phone and Wear AVDs

The canonical pair was established on **2026-10-06**. These are Wear network node IDs, not
ADB device serials; continue to address every ADB command with the discovered serial variables.

| Device | AVD | Wear node ID |
| --- | --- | --- |
| Watch | `wardpulse_wear_round_api36_1` | `502cc269` |
| Phone | `wardpulse_phone_play_api36` | `f71537bc` |

Pair the two AVDs once. Emulator pairing does not require BLE:

1. In Android Studio, open Device Manager, open the watch row's overflow menu, choose **Pair
   Wearable**, select the phone, and continue. With keyboard-only control, press `Tab`, then
   `Down` until the watch row is selected. Press `Tab` twice, moving past the stop button to
   the overflow button, then `Space`; **Pair Wearable** is already selected, so press `Return`.
   Press `Return` again to confirm the selected phone.
2. The assistant creates the ADB bridge and starts the companion activity on the phone:

   ```sh
   am start -n <companionAppId>/.EmulatorActivity \
     --es emulator-name "<wear AVD>" --es emulator-id "<wear node ID>"
   ```

   This command is implemented by `NonInteractivePairing` in Android Studio's
   `plugins/android/lib/android.jar`. The assistant follows
   `[EMULATOR_PAIRING:<state>]` markers in the phone's logcat.
3. In this verified flow, the assistant reaches `CONSENT` and reports **Failed to enable
   emulator pairing** even though the companion activity is open and waiting on the phone.
   This is a timeout, not a failed pair. Complete each consent screen through ADB:

   ```sh
   adb -s "$PHONE_SERIAL" exec-out screencap -p > /tmp/ph.png
   adb -s "$PHONE_SERIAL" shell input tap 782 2240   # More, then I agree
   ```

   Repeat the tap after capturing the next screen. The coordinate is for a 1080×2400 display.
   Prefer the `uiautomator dump` bounds workflow described above over a fixed coordinate.
4. After the companion reports **Connected**, verify both `WearableService` views through
   the [diagnostic output privacy](#diagnostic-output-privacy) guard. Retain connection state
   and expected peer/role matches, not raw service bodies or whole matching lines. Both
   sides must be connected to the intended saved pair; absent or conflicting observations
   remain unproved. Keep literal peer identities private.
5. ADB-driven consent skips the companion's notification-access prompt, so a pair that reports
   **Connected** still bridges no notifications. Grant the listener explicitly, before saving
   the snapshots:

   ```sh
   adb -s "$PHONE_SERIAL" shell cmd notification allow_listener \
     com.google.android.apps.wear.companion/com.google.android.libraries.wear.companion.notification.service.CompanionNotificationListenerService
   ```

   Measured on 2026-10-08. Without the grant a notification posted on the phone never reaches
   the watch. With it the phone logs `WearNotifPipeline: [Sender] Putting notification data
   item /bridger/stream_item:…` and the watch logs `WearServices: [WBridgedItemsController]
   Displaying bridged notification … creatorNodeId=<phone node ID>`.

   A bridged notification does not pass through the watch's own `NotificationManager`, so
   `dumpsys notification` on the watch never lists it and its `NotificationRecord` count does
   not move. Read the watch logcat or the watch screen instead.
6. Save both paired states immediately. Snapshot saving requires `Vulkan = off` in
   `~/.android/advancedFeatures.ini`; otherwise the emulator returns `UNSUPPORTED_VK_APP`.

   ```sh
   adb -s "$PHONE_SERIAL" emu avd snapshot save paired
   adb -s "$WEAR_SERIAL" emu avd snapshot save paired
   ```

For an end-to-end check, start `app.wardpulse` on the phone. The watch logcat must contain
`I/WardPulseSync: Watch summary received.`; all watch-face complications then refresh, and
their values must match the phone panel.

### Restarting a paired emulator set

The pairing record lives on `/data` and survives an emulator restart, including a cold boot
with `-no-snapshot-load`. After boot, both devices still report their pairing configuration,
with the phone's expected stored peer/role match checked privately, but initially report
`IsConnected=false` because the assistant's transient port forwarding ended with the previous
emulator processes.

Restore that bridge without Android Studio:

```sh
adb -s "$PHONE_SERIAL" forward tcp:5601 tcp:5601
adb -s "$WEAR_SERIAL" reverse tcp:5601 tcp:5601
adb -s "$WEAR_SERIAL" shell am broadcast -a com.google.android.gms.wearable.EMULATOR \
  --es operation refresh-emulator-connection
```

Google Play services reports `Emulator connection refresh succeeded.` Within a few seconds,
the watch must return to connected with its expected peer match through the safe diagnostic
observation above; starting `app.wardpulse` on
the phone must again produce the WardPulse receipt log on the watch. When a known pair reports
`IsConnected=false`, restore this bridge first. Do not run the pairing flow again.

Do not rely on restoring the phone's `paired` snapshot. On the canonical phone AVD,
`emulator @wardpulse_phone_play_api36 -snapshot paired` loaded the snapshot and then failed
twice with `ERROR | Failed to find EmulatedEglImage`; its `config.ini` has `hw.gpu.enabled=no`
with `hw.gpu.mode=auto`. Start that AVD reliably with
`emulator @wardpulse_phone_play_api36 -no-snapshot-load` instead. The pairing record remains on
`/data`, and the canonical Wear AVD's paired snapshot restores normally.

### Preserving emulator state

Treat the configured AVDs as persistent development devices:

- Before risky operations, verify that suitable recovery protects the current state. Reuse an
  existing compatible, verified restore point when it still covers that rollback scope;
  otherwise save the necessary pre-change state, with Vulkan disabled as described above.
- Do not delete or recreate an AVD to troubleshoot it. That discards Google sign-in, browser
  sessions, system settings, keyboard layout, and any existing phone-watch pairing.
- Never run `pm clear com.google.android.gms` on the watch; it destroys the pairing record.
- Background WardPulse before a bounded `am kill app.wardpulse`; do not force-stop the app
  to manufacture a restart or quiet interval. A successful command or HOT resume does not
  prove death: verify the old process identities disappear and a subsequent launch creates a
  new process, while checking scheduled-work preservation. The gate's `stop_app` in
  `tools/test-phone-watch-sync/run.sh` re-evaluates ordinary kill within one overall
  15-second request/wait deadline and respects pending KILL intent; intent is not death.
  If that proof is unavailable, report HOLD. This rule is scoped to WardPulse; the targeted
  `am force-stop com.google.android.wearable.sysui` recovery above remains valid.
- Size `/data` before first boot. Its size is fixed once materialized, and snapshots prevent
  `qemu-img resize` from changing the image afterward.

**Named snapshot retention.** Full-state snapshots preserve OS/app/user data and can include
large RAM images; they are recovery points, not a permanent record of every test. Read-only
inspection, screenshots and routine non-destructive navigation do not warrant a fresh whole-RAM
snapshot each time. Keep durable sanitized QA evidence instead. This does not waive recovery
before an actual risk or permit an old restore point that no longer covers current user state.

The WardPulse default per AVD is **one verified current/recovery anchor plus one transient
pre-change named snapshot**, not a quota to fill, platform limit or automatic deletion threshold.
Do not create checkpoints merely to fill that allowance. Quick Boot is separate; do not change
its settings for housekeeping. Additional active-case checkpoints,
paired anchors or other justified pins need a recorded recovery purpose, owner/dependency and
review date or acceptance boundary. Reaching that date triggers review, not blind deletion.

Inspect allocated disk usage and named-snapshot counts before adding checkpoints and when a
case completes. Keep concise ignored working notes with AVD/snapshot identity, allocated
size, purpose, verification/compatibility limits, active dependencies, review/expiry trigger and
keep/retire decision; no credentials or raw user payloads. After verified restoration or
acceptance of the intended state, retire superseded task snapshots through supported snapshot
management, such as the emulator's Snapshots pane Delete action. Preserve required recovery,
paired/active checkpoints and other owners' state; no name, age or count alone establishes that
a snapshot is disposable.

For already-authorized retirement of a task's own superseded transient, the operator's existing
working notes and keep/retire check suffice; no fresh approval or independent agent review is needed.
For bulk historical cleanup, review the exact keep/retire manifest under applicable authorization;
a storage-diagnosis question alone does not authorize that deletion. Both paths require verified
intended/restored state, suitable recovery kept, no active dependency or other-owner impact, and
supported snapshot management. Without applicable authorization, report candidates only. Never
blindly remove RAM/image files or snapshot directories, make a new full-AVD copy, wipe/recreate
an AVD, lower its RAM, resize partitions or change configuration merely to conceal growth.
Preserve current running state, userdata, sign-ins and pairing; configuration changes can also
invalidate snapshots. Use supported management without disturbing active work.

Respect the canonical phone's failed `paired` restore documented above: it is not verified
rollback coverage. The cold-boot route preserves data across restart, not a prior version of
mutated userdata. If suitable recovery for the intended risk is unavailable, report HOLD rather
than proceeding without it or repeatedly creating unverified snapshots.

## Watch Face Format

The legacy watch face is a separate resource-only package in `apps/watchface_wff/` (Phase 13
concentric baseline — `docs/product/WATCH_RING_DESIGN.md`). Its resources are also canonical
inputs to the [bundled Push APK](#watch-face-push-builds); the table describes legacy packaging:

| Setting | Value | Purpose |
| --- | --- | --- |
| Watch Face Format | version 2 | Concentric remaining arcs + strip accents via WeightedStroke / RANGED_VALUE ColorRamp (Wear OS 5+). A scene takes at most **8** `ComplicationSlot` elements — the same in v2/v4/v5, so a raise cannot buy more |
| Application ID | `app.wardpulse.watchface` | Independent watch face package |
| Minimum SDK | API 34 | Minimum runtime for WFF v2 |
| Compile SDK | Android SDK 37.1 | Shared Android build baseline |
| Target SDK | API 36 | Shared Android target baseline |
| Android Gradle Plugin | 9.3.0 | Shared Android build plugin |
| Gradle | 9.6.1 | Checked-in wrapper version |

The legacy build needs no Push runtime library. `just validate-watchface`
downloads the official validator 1.7.0 once from GitHub asset `646791144`, checks
SHA-256 `fb3262aa146de24c169a1d451901b4df2bfedca28a27c3c168a487e02d393771`, and caches it
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`.
Upstream assets can be removed or replaced; the explicit asset/checksum pair pins content
without guaranteeing availability. Validate, build, and lint locally with:

```sh
just validate-watchface
just check-watchface
just build-watchface
```

Install and select it on exactly one Wear target:

```sh
export ANDROID_SERIAL="$WEAR_SERIAL"
just run-watchface
```

The preview image is generated from the Primary baseline by
`node tools/render-watch-ring-designs.mjs`, with the quiet watermark composed in at the box
`watchface.xml` gives it. After visual changes, use a fresh interactive-mode capture from the
canonical round Wear AVD to verify the face; do not produce the asset from that capture.

Do not use the picker to verify that asset. Whether any surface displays it is not settled: the
2026-10-09 claim that the picker shows it was inferred from `watch_face_info.xml` rather than
seen, and the one direct reading — `emulator-5554`, 2026-10-11 — shows the picker rendering the
face live, watermark and preview complication data, with nothing of the file in it. What **is**
settled is that it ships. To check that, pull the installed package and compare the drawable
against the tree:

```sh
adb -s "$WEAR_SERIAL" shell pm path app.wardpulse.watchface
adb -s "$WEAR_SERIAL" pull <the apk path> /tmp/wf.apk
unzip -o /tmp/wf.apk res/drawable/preview.png -d /tmp/wf
compare -metric AE /tmp/wf/res/drawable/preview.png \
  apps/watchface_wff/src/main/res/drawable/preview.png null:
```

`0` means the generator's output reached the device intact; that was the reading on 2026-10-11.
See *Previews are generated — and the picker's showed the first non-goal* and *Surface
correction 2026-10-11* in `docs/product/WATCH_RING_DESIGN.md`.

### The package ships no code, and the system owns its complication slots

Measured on `emulator-5554`, 2026-10-09. The point is not bookkeeping: it decides who can
change which provider sits in which slot, and the answer is never WardPulse.

- **The APK contains no code.** `unzip -l` on `WardPulseWatchFace-debug.apk` lists **zero**
  `.dex` entries, and `apps/watchface_wff/src/main/AndroidManifest.xml` declares
  `android:hasCode="false"` with no `<activity>` and no `<service>` — only the watch
  `<uses-feature>`, the `com.google.android.wearable.standalone` metadata, and
  `com.google.wear.watchface.format.version`. The package is resources and nothing else.
- **A Google process draws it.** `adb shell dumpsys wallpaper` reports

  ```text
  mWallpaperComponent=ComponentInfo{com.google.wear.watchface.runtime/com.google.wear.watchface.runtime.DeclarativeWatchFaceRuntime0}
  ```

  The package `com.google.wear.watchface.runtime` declares `DeclarativeWatchFaceRuntime`,
  `DeclarativeWatchFaceRuntime0` and `DeclarativeWatchFaceRuntime1`. A WFF face is not its own
  wallpaper service; it is data that Google's runtime interprets, and `app.wardpulse.watchface`
  never runs.
- **The provider chooser is a system activity.**
  `com.google.android.clockwork.sysui.experiences.complications.ProviderChooserActivity` lives
  in `com.google.android.wearable.sysui`, beside the system providers
  (`DayOfWeekProviderService`, `StepsProviderService`, `SunriseSunsetProviderService`) and the
  face picker, `mainui.module.watchfacepicker2.WatchFacePickerAllFacesActivity` in that same
  package.

So a WFF face cannot own an editor: there is nowhere in it for one to run. This is the shape of
the format, not a gap in ours. Everything the face gets to say about a slot it says in markup —
`isCustomizable`, `supportedTypes` (`EMPTY` among them) and `DefaultProviderPolicy` — and the
wearer changes the rest in the system UI. The WardPulse phone app is excluded twice over: it has
no API that writes another package's slot configuration, and the configuration does not belong
to our package in the first place. `ComplicationDataSourceUpdateRequester` only asks our own
provider services to refresh the data they already supply.

**Observed on 2026-10-13.** The system chooser for the central upper cell was reached on the
canonical Wear AVD. Its UI hierarchy showed enabled, clickable `Empty` and `Battery, Wear OS`
buttons at `[20,123][364,227]` and `[20,235][364,339]`, respectively. This verifies that the
chooser offers an empty entry for that cell. No selection was made: actually clearing the
cell and rendering a custom Status complication remain unverified.

### Watch Face Push builds

Implementation and local development acceptance recorded **2026-10-16**: final debug
builds, development signer/artifact binding and API33/API34/API36 emulator observations
passed within the [recorded scope](product/RELEASE_CHECKLIST.md#watch-face-push-acceptance).
Production signing, Play delivery, API35 and physical hardware remain separate. This
addition does not refresh the historical verification dates above.
The [Push module](../apps/wear_android/watchface_push/README.md) packages the canonical
`apps/watchface_wff/src/main/res/` as `app.wardpulse.watchfacepush.main`, WFF 2, minimum API 34,
with no application code. Legacy packaging and its independent workflow remain unchanged.
The Wear host minimum is API 33 and uses `androidx.wear.watchfacepush:watchfacepush:1.0.0`.
Factory support is checked before manager creation/use: API 33 keeps the dashboard usable
but cannot install this face; API 34/35 offer separate WFF installation, and supported
Wear OS 6+ devices offer Push.
The phone minimum and phone-to-watch transport remain unchanged.

Owner supplies ignored repository-root `watchface-push-debug.properties` and
`watchface-push-release.properties`. Each uses the names `storeFile`, `storePassword`,
`keyAlias` and `keyPassword`; values stay private. The keystore path must be absolute and
outside the repository. Keep the development identity persistent outside build outputs,
including across `clean` and N-to-N+1 builds. CI provisions its own development identity
only. The build does not provision Owner Push identities.

`RequirePushSigning` in the [Push build script](../apps/wear_android/watchface_push/build.gradle.kts)
rejects missing/invalid signing and reuse of a configured Push development certificate for
release. Neither variant falls back to a host key. `PrepareDefaultWatchFace` in the
[Wear host build script](../apps/wear_android/app/build.gradle.kts) verifies that the signed
APK certificate differs from the selected host certificate, including debug. The existing
host `key.properties` / `wardpulseRequireReleaseKey` guard and shared phone/Wear identity
still apply; Push release signing is additional. See [Signing](product/RELEASE_CHECKLIST.md#signing).

From `apps/wear_android/`, after private development signing setup, build the current
bundled face through the ordinary graph:

```sh
./gradlew :app:assembleDebug
```

`wardpulsePushVersionCode` defaults to 5 and accepts a positive Android integer. Keep the
Push package and certificate identical for N/N+1 development builds. This input belongs to
the independent Push package; it does not set the Wear host version. The adaptive
compatibility allocation now uses phone 3/Wear 4/legacy 2/Push 5, all versionName 0.1.0;
only the guarded Push default advances 3→5 without a release cut. Preserve historical
candidate 4 flags/instrumentation, the actual 3→4 journal and all release-bridge guards.
Preserve the actual old code 1 receipt and unobserved new-Wear4/old-Push1 and explicit 1→2
steps. Installing Wear 4 was followed by Push 2 before explicit update, with an unknown
trigger; the subsequent 2→3 manager update was also unobserved. The later guarded normal UI
4→5 Update requires fresh installed Push 4/hash/signer, owned manager slot, eight choices and
quiet-writer proof with Legacy kept active, returned same-slot identity and separate settled
retention. Unexpected advancement stops that witness: no code 6, replay, downgrade, reset or
invented button success. Later retained-Push selection/rendering is separate HOST work;
bundled installation proves no explicit update or activation.
Follow the [current qualification](product/RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30);
never rebuild a synthetic old baseline, downgrade, reinstall or reset. Follow the central [release version scheme](product/RELEASE_CHECKLIST.md#release-versions)
and [ordinary release flow](#release-artifact-builds). Release needs both host release
configuration and separate Push release configuration.
The normal variant graph consumes a signed APK artifact from `:watchface_push`, validates
it, generates variant assets/resources and packages the host. There is no nested Gradle
invocation, manual APK copy step, token substitution or source edit.

`PrepareDefaultWatchFace` owns the nontransitive Google Maven dependency
`com.google.android.wearable.watchface.validator:validator-push-cli:1.1.0-alpha01@jar`
and `validatorSha256`, pinned to
`04dc20a0994df3eaebf025e107f7589c147b2ce8a2c628745e01a5c0a63fe4dd`.
The [official artifact](https://dl.google.com/dl/android/maven2/com/google/android/wearable/watchface/validator/validator-push-cli/1.1.0-alpha01/validator-push-cli-1.1.0-alpha01.jar)
is resolved through the existing Google Maven repository. Review the version, checksum and
CLI output contract together when changing the pin; this is a build-time tool, not a runtime
dependency or a second download helper. The XML validator above retains its separate purpose.

The producer invalidates old outputs, checks the JAR checksum before execution, verifies
the signed APK and passes its absolute path as `--apk_path` with `--package_name app.wardpulse`.
It requires official validation success and one token, without logging tokens or raw output.
Only success publishes the exact validated bytes and matching token under ignored
`app/build/generated/defaultWatchFace/<variant>/`: `assets/default_watchface.apk` and
`res/values/default_watchface.xml` containing `@string/default_wf_token`. The host manifest's
`com.google.android.wearable.marketplace.DEFAULT_WATCHFACE_VALIDATION_TOKEN` references it.
APK/resources, version, signing identity and validation inputs invalidate the generated pair;
failed validation leaves no published pair. No APK or token belongs in source control.

See [the acceptance record](product/RELEASE_CHECKLIST.md#watch-face-push-acceptance) for
completed cold/warm validation, final signed-artifact inspection, real N1-to-N2 upgrade,
API33/API34/canonical observations and their remaining release/platform boundaries.
The injected-manager tests do not establish unobserved platform scenarios. That record's
post-DONE Owner documentation build/browser and output-handoff procedure belongs to the
dated 2026-10-16 Push task.

## Release artifact builds

The [release checklist](product/RELEASE_CHECKLIST.md#release-versions) owns the package and
version table and WardPulse's odd-phone/next-even-Wear code convention. All 0.1.0 RC
versionNames remain 0.1.0. Root resolves first-publication versus existing signing and
uploaded-version history, then supplies authorized private configuration only after Runner
DONE and retired ownership, as required by [Signing](product/RELEASE_CHECKLIST.md#signing).
Runner and its operator do not inspect those private inputs.

From the repository root, use the unchanged guarded recipes:

```sh
just bundle-phone
just bundle-wear
just bundle-watchface
```

These produce separate phone and Wear AABs for `app.wardpulse` and a legacy WFF AAB for
`app.wardpulse.watchface`. Each requires the existing ignored root `key.properties` through
`wardpulseRequireReleaseKey`. Phone includes the Android Rust build. Wear additionally
requires separate Push release configuration; its ordinary graph signs and validates the
Push APK, then embeds the exact APK/token pair. The independent guarded Push default is
5 for the current integration allocation; this does not prepare a release. Do not bypass
the guards or override build-name/build-number to conceal source versions.

Follow [local signed-RC acceptance](product/RELEASE_CHECKLIST.md#local-signed-rc) for fresh
artifacts, manifest/version/ABI/certificate inspection, exact APK/token binding, native ELF
and packaging alignment, and private receipts. Reviewed source, locally inspected signed
artifacts and [Play distribution acceptance](product/RELEASE_CHECKLIST.md#play-distribution)
are separate gates. A successful local build does not verify Play's delivered signer or
close runtime, API35, physical-device or unobserved Push recovery acceptance.

## Routine Verification

Verify installed versions and packages:

```sh
flutter --version
dart --version
java -version
rustc --version
cargo --version
android --version
android --sdk="$ANDROID_HOME" info
android --sdk="$ANDROID_HOME" sdk list
adb version
emulator -version
flutter doctor -v
```

Run WardPulse checks:

```sh
just check-core
just check-phone
just build-android-rust
just check-wear
just check-watchface
```

Run the phone Android acceptance checks:

```sh
just build-android-rust
(cd apps/phone_flutter && flutter build apk --debug)
ANDROID_SERIAL="$PHONE_SERIAL" just install-phone
```

The default debug build includes every configured ABI. On a storage-constrained target, build
only the matching architecture before running the same installation recipe:

```sh
# x86_64 emulator
(cd apps/phone_flutter && flutter build apk --debug --target-platform android-x64)

# arm64 device
(cd apps/phone_flutter && flutter build apk --debug --target-platform android-arm64)
```

`install-phone` deliberately leaves compilation and ABI selection to the preceding build. It
requires an explicit phone serial because the phone and Wear shells share `app.wardpulse`, then
compares the package's `lastUpdateTime` before and after `adb install -r`. Comparing those two
values supports a first installation and does not depend on the device clock, which can lag after
an emulator snapshot is restored.

Do not treat a shortened `adb` transcript as installation evidence. A command such as
`adb install ... | tail -1` returns `tail`'s status rather than `adb`'s and can hide the failure
line. Even visible output does not prove that the package changed, so the recipe also fails when
the post-install timestamp is missing or unchanged.

For Codex acceptance, open the phone **Providers** tab → Codex / plan row, start sign-in, open
the external OpenAI page, and enter the one-time code. Plan usage, purchased usage, and
platform spend are on by default; any can be hidden via Settings consumption-display toggles
if at least one surface remains. The OAuth session stays in phone-secure storage and does not
require a Codex CLI, local server, or `adb reverse`.

### Wear instrumentation provisioning order

The default Wear runner is `IsolatedWearRunner`. It selects its test-owned application only
through `newApplication` and requires a compatible target with the full `MainActivityDependencies` ABI.
The [isolated default instrumentation](../apps/wear_android/README.md#isolated-default-instrumentation)
keeps all original 40 tests and real owner/lifecycle/durable-consent guarantees, with private
fixture stores and a recording refresh sink. Test-APK installation alone does not provide
the target seam. The earlier seam-unavailable observation belongs to its original baseline bytes;
preserved Wear APK `8f3ec6b2…` defines `MainActivityDependencies` and both `WatchSummaryStore`
constructors. Class presence proves neither the full required ABI/isolation nor candidate parity.
Default 40 must validate the current candidate under its permitted target/artifact order; old
asset-3 target smoke is not built asset-5 candidate acceptance. That acceptance remains Pending
until compatible ordered provisioning and native execution; no early replacement is authorized.
Its attribution regressions use private stand-ins for equal and newer normal-store values;
byte equality is not evidence that a test published to normal storage. Actual backing-store
identity, constructor routing and recording-sink dispatch remain the isolation evidence.

For item12, preserve installed old Round Wear 4/bundled asset 3/Push 4, Legacy active and the
actual 3→4 journal. Do not replay that witness or install a new target as recovery. Current
operation-specific order is documented under [datasource observations](#guarded-datasource-observations),
[client metadata](#independent-client-metadata-observation), [typed configs](#typed-own-provider-config-observation)
and [inventory/peers](#owned-push-inventory-and-connected-peers). Scoped 2026-10-30 owned-Push,
connected-peer and typed own-provider reads succeeded. Client acquisition was **uninvoked** after
ambiguous `beforeResource`; its exact failing suboperation/cause was not established. This is
not an API denial, requester-mapping acceptance or native paint, and read receipts authorize no mutation.
The [UI evidence](../.agents/skills/ui-verification/references/state-and-artifacts.md) and
[finalization reference](../.agents/skills/finalization/references/commit-message.md) corrections were
applied and reviewed in `5b6486e` and `5b5df97`. Current mapping, default-40 and native acceptance
remain Pending. Separately reviewed test-only provisioning does not authorize early seam-bearing
target replacement; expose any genuine target dependency first. Live phone 1→3/sync and UI
Update/selection still require their operation-specific authority and custody. Before normal UI
4→5, prove inactive Push 4's eight choices and owned slot; active Legacy's selections do not supply
that proof. Keep Legacy active during the update and require separate settled retention.

**Historical nine-step allocation (2026-10-30).** The
[qualification](product/RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30) retains
all six compatibility cells, Root-reviewed forward-only reconciliation for unavailable history,
that allocation's Native inventory and all nine mandatory HOST duties. Separate current runs
use their own admitted Native inventory. All HOST starts follow the whole owning execution DONE,
run-owned process retirement, owning CLI exit if used and fresh separate public/OS idle;
they never gate Native commits. Nontarget full
`just check-wear`, `just check-watchface`, pure complete `just check-phone` and final docs/
fixtures/release checks may then run without install/adb or changing installed phone 1.
Full device tests, both-shape first/separate-settled endpoints/transitions/true-AMBIENT,
phone retention/sync, recovery and later healthy public guidance/captures remain mandatory.
Physical-phone action remains forbidden and physical-watch acceptance deferred. Item12 stays
open; this historical allocation does not claim current check/device acceptance.

**Recorded dependency qualification (2026-10-30, Source `5b5df97`).** Full warm, empty-cache
and same-cache reuse `just check-wear` completed successfully. Actual resolved client 1.2.1 AAR
SHA-256 `3392836298972c6820c7a8179c89bb37fc97f461cc991368f4cb001c236bafa0` matched official bytes.
Retain that evidence; do not repeat unchanged dependency checks for reassurance or infer native access.
For a newly required qualification, run the complete check on a network-capable HOST with
`GRADLE_USER_HOME` pointing to a **new, empty, task-owned cache** under `LOCAL_ARTIFACTS/`.
Record its exact path and command. Verify the
actual download/resolution of `androidx.wear.watchface:watchface-client:1.2.1`, the resolved
AAR's SHA-256 against official artifact provenance and complete check success; repeat the
same check with the same cache to prove reuse. Set `ITEM12_GRADLE_CACHE` to the absolute
path of a newly created, verified empty task-owned directory. From the repository root:

```sh
GRADLE_USER_HOME="${ITEM12_GRADLE_CACHE:?Set the task-owned cache path}" just check-wear
```

After recording resolution, checksum and complete first-run success, execute that same
command with the same path again and record the reuse outcome.

Do not seed, delete or repurpose shared caches, substitute the saved sources/POM for Gradle
resolution, or claim a successful build proves native access. Record resolution/checksum and
both full outcomes, including failures. These non-installing HOST checks follow whole Runner
DONE, process retirement, owning CLI exit where applicable and fresh idle ownership; they are
not Native-commit prerequisites. New or changed qualification remains Pending until executed;
the recorded completed cache checks above are not pending. After operation-specific identity,
dependency and retention review admits the required provisioning,
`just test-wear-device` explicitly provisions the rebuilt seam-bearing target and test APKs
through `connectedDebugAndroidTest`; verify the retention policy below first, confirm the
original 40 tests/manual exclusion, then recheck retained Push 4, bindings and active state.

#### Guarded Push witness

**Historical candidate 4 / 3→4 contract.** Keep the flags, instrumentation, original receipts
and actual one-dispatch journal below unchanged. The installed baseline has since reached
Push 4 with Legacy active. These historical commands are not authorization to replay the
operation, repeat its picker selection or replace the old host/asset 3. Current Source 5
uses the separately guarded normal UI path in the qualification above; all target operations
remain held for the capability/guard phase. The original prospective procedure follows.

This is HOST-only after whole Runner execution DONE, owned-process retirement, owning CLI
exit where applicable and fresh separate idle ownership. Source/semantic review is not native
acceptance. Keep the original target APK and asset 3 throughout this sequence; a failed or
uncertain witness forbids subsequent target installation. Never run a connected/default suite,
`run-wear`, sync recipe or other target installer first. Receiver disable, permission grant,
reset, downgrade, candidate substitution and version loops remain forbidden. The harness
never creates, activates or reselects a face. The completed execution's frozen operator
no-activation inputs are unchanged; the adopted post-DONE scope below is a new HOST boundary.

**Adopted HOST scope, 2026-10-29 — existing-Push baseline.** After whole DONE, owned-process/
CLI retirement and fresh idle, HOST is permitted **one** ordinary system-picker selection of
a pre-existing, configured, owned Push 3 instance on the verified canonical **Round AVD**.
Record original Legacy identity/settings, available native state and private recovery/
quiet-writer/bridge evidence, then the deliberate changed baseline. Preserve original host 4/
asset 3 bytes. No new instance, SDK/app activation, permission, binding/style edit or reset is
included. Unproved identity or safe exact restoration stays Pending; no route success is promised.

Before test-only provisioning, independently record host/asset/APK/signer, selected existing
package/instance and available native state with its limits. Provision only the test APK,
recheck unchanged host/asset, then use read-only stock `probeBaseline`: its first eight rows
omit the three slot/instance/configuration hashes discovered before SDK dispatch. Require
complete authoritative selections and all actual guards; cached delivery/defaults are insufficient.
The first post-provisioning fingerprint cannot prove earlier full selection retention. After
the genuine stock result, separate later whole original, cleanup and instrumentation retirement,
restore exact original configured Legacy selection/settings and normal effective data/bridge
state while reconciling newer writes and retaining owned Push 4. The genuine witness must
still precede target provisioning; retries, downgrades and an immediate-active oracle remain forbidden.

From `apps/wear_android`, build the signed, officially validated candidate into the **test**
APK without installing anything:

```sh
./gradlew --no-daemon :app:assembleDebugAndroidTest -PwardpulseNativeCandidate=true -PwardpulsePushVersionCode=4
```

Before provisioning, independently inspect the installed target APK/code/signer, its embedded
asset's package/code/signer/hash, installed Push package/code/signer/hash, AVD name/image and
physical display. Bind the actual selected serial to the canonical Wear AVD using `emu avd name`;
the instrumentation independently checks QEMU, the AVD-name property, watch feature, API 36,
image fingerprint and unoverridden 360×360 square or 384×384 round display. Preserve active
runtime/instance, lower bindings, upper choices, summary, consent, settings and bridge state.
Review compatible signing and the packaged test manifest's two instrumentation entries during
HOST. Source keeps the configured isolated runner first and stock runner second: AGP rewrites
the first instrumentation element with the configured runner name. If baseline SDK/classloader
access is unavailable, leave Pending; never install the seam as recovery.

Provision only the generated test APK (never the local target APK):

```sh
adb -s "$WEAR_SERIAL" install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
```

Re-observe target APK/asset hashes and identities after provisioning; require equality to the
independent pre-provisioning receipt. The harness additionally checks those expected hashes
before dispatch and through later observation. Use the stock entry
`app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner`, with **one explicit method** of
`app.wardpulse.wear.nativeintegration.NativePushUpdateTest`. The isolated entry would load an
ABI absent from the baseline; it must not be used here. Never invoke stock discovery/default
tests. The three `NativePushGuardTest` cases can separately be explicitly selected by class;
they use memory, private temporary files/descriptors and fixed shell-output fixtures, without
querying installed packages or accessing the manager/live stores.
The three update-class cases are manual; together with the three Push guard, six
datasource, eleven client, six typed-config and nine inventory cases, `IsolatedWearRunner`
excludes all thirty-eight manual cases and keeps the original default 40 tests.

After the system-authority correction, require a fresh complete warm `just check-wear`
after the last Source fix, rebuild candidate/test-APK provenance, then install only the test
APK. Pass all seven existing private Android guards before exactly one corrected read-only
stock `probeBaseline` within the existing continuous Push 3/wf16 witness. That probe itself
exercises the changed observer; do not add another live observer invocation. Do not select the
face again or replace the original host/asset 3. Prior dependency/cache/checksum receipts apply
only to the unchanged dependency graph; they do not build or exercise corrected source.

`NativePackage.read` in
[NativePushState.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativePushState.kt)
uses the existing UiAutomation owner only for a fixed Push package-path enumeration with a
success-completion marker. Its bounded complete output must contain exactly one allowlisted
base-APK path and no splits or extra records. Normal target-UID file access then supplies the
full installed APK hash, real archive package/code/single signer and resource-table hash;
rehashing and re-resolving detect changes without promising atomic observation. The same
reader serves later datasource/client callers and post-update resource verification, without
hidden-package metadata lookups or shell APK copying. A path/hash alone does not prove archive
or signing capability: null, denied or unavailable evidence leaves the witness Pending before
dispatch. Keep SDK manager calls on the unchanged target context and retain every slot,
selection, active-instance, host/asset and one-dispatch guard.

`NativeDiagnostics` reports closed phases/categories, contemporaneous bounded observation
sizes/hashes/completeness, inventory flags and semantic matches. Caller wallpaper API
null/match/mismatch/error is diagnostic only: even an error cannot bypass System proof or
replace the first actual guard failure, which survives cleanup. Raw dumps, payloads, exception
text/causes, tokens, opaque IDs and arbitrary guard strings are excluded. The old generic
rejection's exact cause remains unproved; the unsupported retriever query was never reached.
No query failure, server rejection or completed HOST acceptance is claimed. Fresh normal-UID
archive/probe, the genuine single update, separate settled evidence, restoration (including
original Legacy15 selection/settings) and owner retirement remain HOST obligations.

Supply these fresh HOST expectations as `am instrument -e` strings. SHA-256 values use lowercase
hex; fingerprint/instance/slot strings are hashed as UTF-8 **without** a trailing newline.

| Argument | Expected input |
| --- | --- |
| `wardpulseNativeIntegration` | Literal `push-3-to-4` |
| `expectedAvd` | Canonical `wardpulse_wear_square_api36_1` or `wardpulse_wear_round_api36_1` |
| `expectedFingerprintSha256` | Hash of the actual `Build.FINGERPRINT` |
| `expectedHostApkSha256`, `expectedHostSignerSha256` | Original installed host APK and single signer hashes |
| `expectedAsset3Sha256` | Exact installed host's Push asset 3 APK hash |
| `expectedPush3ApkSha256`, `expectedPushSignerSha256` | Installed Push 3 APK and single signer hashes |
| `expectedRuntime` | Actual `DeclarativeWatchFaceRuntime0` or `DeclarativeWatchFaceRuntime1` |
| `expectedResourcePackage` | Actual active package; legacy-only evidence leaves Push configuration retention Pending |
| `expectedSlotSha256`, `expectedInstanceSha256`, `expectedConfigurationSha256` | Owned slot and Push-instance identities; configuration requires independent actual selection records, never cached delivery |

First select `probeBaseline`. It requires the first eight rows, checks all applicable native
records and reports slot/instance hashes and a separate cached-delivery provenance hash,
without writing an attempt or changing the manager. That diagnostic line is not a passed
binding/choice check. Successful selection discovery also emits a configuration hash.
Configuration hashing uses user-style content followed by ascending
slot rows `id|enabled=true-or-false|selected-package/class`, with `<none>` for an explicitly
unselected provider, separated by newlines without a final newline. Selection records must
cover every slot and identify the resource package and actual instance; see `NativeRenderer`
and `NativeSelections` in
[NativePushState.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativePushState.kt).
Neither default policy nor a cached `ComplicationData.dataSource` is a current selection record:
a chooser change/reset can leave old delivered data intact. `NativePushDevice.readRenderer`
uses bounded read-only observations through the existing UiAutomation owner, rather than
caller-visible wallpaper identity or the unsupported cross-package retriever. It reads the
actual current user and System display/component with its matching live connection. Around
`wear_service` active configuration it requires matching semantic System/native frames: scoped
service user/display/component, one native registry/engine instance, resource package, style
and enabled slots. Relative counters and cached delivery do not define semantic identity.
This bracketing is not atomicity or a freshness guarantee; every shell descriptor/stream is
owned and closed on success or failure.

Only the controller's `activeConfigs` supplies selections. Its favorite/resource must join
one IDLE non-fallback ANDROIDX active facade, the explicit current active engine and current
wallpaper component, then the observed native resource/instance. Favorite and native instance
are independent opaque identities; never construct `wfId` from a favorite. Configuration row
IDs supply neither slot IDs nor canonical/requester IDs; C3 provenance remains separate.
No new across-update favorite-ID guarantee is claimed. Expected inputs only compare with
observations. Default/fallback or lock-only wallpaper, caches, databases, history and defaults
cannot complete this chain.

Declared size, actual count, unique complete slot coverage and enabled states must agree.
Missing, duplicate, conflicting, transitional, pending-action, malformed or unresolved scoped
evidence remains **Pending/HOLD**. Only explicit `provider=null` means an empty choice;
missing provider evidence is unavailable. All five exact lower bindings and all three upper
choices retain the existing fingerprint encoding. Configured selection type retains its
configuration meaning; it is carried independently of delivered/NoData/overridden values and
supported-type contracts, without a cross-domain equality or rejection guard. Actual native
and SDK ownership proof still needs HOST execution. Never change choices or inject data to
manufacture preconditions. Legacy-only evidence cannot verify the inactive Push configuration
or authorize target replacement. The harness never creates, activates or reselects an instance.
The single adopted picker selection established the historical Push 3/wf16 baseline;
preserve subsequent Push 4/Legacy-active and restoration receipts. Make no new selection
during this allocation. Original Legacy15 settings/choice restoration still needs independent
verification; active Legacy alone does not prove it.

Only with the actual Push instance and authoritative selection preconditions established may
one `updateOwnedPush3To4` invocation dispatch. Successful discovery supplies the selection
fingerprint to the dispatch guard; unavailable evidence stays Pending. Never bypass a Pending
probe. The command shape, with the values above independently populated in the named shell
variables (the probe uses the same command with its method name and omits the last three
hash arguments), is:

```sh
adb -s "$WEAR_SERIAL" shell am instrument -w -r \
  -e class app.wardpulse.wear.nativeintegration.NativePushUpdateTest#updateOwnedPush3To4 \
  -e wardpulseNativeIntegration push-3-to-4 \
  -e expectedAvd "$NATIVE_AVD" -e expectedFingerprintSha256 "$NATIVE_FINGERPRINT_SHA256" \
  -e expectedHostApkSha256 "$NATIVE_HOST_SHA256" -e expectedHostSignerSha256 "$NATIVE_HOST_SIGNER_SHA256" \
  -e expectedAsset3Sha256 "$NATIVE_ASSET3_SHA256" -e expectedPush3ApkSha256 "$NATIVE_PUSH3_SHA256" \
  -e expectedPushSignerSha256 "$NATIVE_PUSH_SIGNER_SHA256" -e expectedRuntime "$NATIVE_RUNTIME" \
  -e expectedResourcePackage "$NATIVE_RESOURCE_PACKAGE" -e expectedSlotSha256 "$NATIVE_SLOT_SHA256" \
  -e expectedInstanceSha256 "$NATIVE_INSTANCE_SHA256" -e expectedConfigurationSha256 "$NATIVE_CONFIG_SHA256" \
  app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner
```

`AttemptJournal` retains the dispatch boundary and returned identities privately; never delete
it to retry. SDK failure/disconnection/crash can mean uncertain advancement. Preserve the host
and record actual installed state; do not repeat the update. Await every owned SDK callback
and descriptor cleanup. No timeout establishes remote completion, and a hanging owner is not
retired. No immediate `isWatchFaceActive` query is made after updating.

Keep the original host/asset through separate later native observations and select
`observeSettledUpdate` once with the same expectations. It reads the verified journal, checks
installed candidate bytes/resources, slot and retained native configuration, and captures one
private original frame only when the updated Push face's own instance and independent actual
selection records are available. The receipt keeps Push configuration retention and target
replacement Pending until that proof; a legacy screenshot or SDK-result verification cannot
substitute. Missing selection records or an unavailable inactive Push instance fail Pending,
and no target replacement is admitted. Inspect the first complete unobscured PNG before batching;
notification/editor overlays invalidate visual acceptance. Use this instrumentation's single
UiAutomation; no concurrent `uiautomator` hierarchy owner. Supplied/last-frame substitutes,
sleeps, timing retries and hidden state normalization are excluded. An absent verified result
or missing native provenance remains Pending. The harness changes no summary/consent/settings,
choices or bridge; do not blindly restore older values over legitimate producer writes. Verify
normal effective data/restoration independently, retain intended version advancement, close
this instrumentation owner and preserve private receipts. See
[native integration ownership](../apps/wear_android/README.md#guarded-native-push-integration).

The historical provisioning gate required successful witness, separate settled evidence,
restoration and owner retirement before ordinary rebuilding **without candidate flags** and
Wear 4/asset 3/signing verification. Current Source 5 provisioning remains held under the
qualification above; preserve the original host/asset for capability work. Later rebuilt-host
evidence cannot replace pre-replacement evidence. The 3→4 witness closes neither the utility button nor
missing 1→2/2→3 manager evidence, old-Push1 matrix gaps or UNKNOWN historical causality. All
unexecuted builds, native routes, effective restoration and visual acceptance remain Pending.

#### Guarded datasource observations

These are later HOST-only observations, after whole execution DONE, all owned-process
retirement and separate fresh public idle. Compilation, guard execution and any seam-bearing
target provisioning require separately reviewed HOST order. Preserve original Round Wear 4/
asset 3/Push 4 and Legacy bytes/selections; Source asset 5 belongs to the later normal UI
Push 4→5 update. Expose a genuine compiled-target dependency and blocked phase without
installing a replacement to manufacture read capability. Production schema, normalization,
settings, consent and datasource behavior stay unchanged.

Select only one explicit `NativeDatasourceTransitionTest` method using the **stock** runner
and literal `wardpulseNativeIntegration=normal-delivery`. `probeDelivery` is read-only apart
from private evidence files. `NativeReadAdmission` requires canonical emulator/image/display
and actual current caller UID/package/APK/signer. The shared mapping reader checks current
resource/runtime APK/signer, active instance/configuration, full-eight selections and intended
targets. Current mapping/frame reads require no historical SDK-update entry resolution,
journal, old package cohort or quiet
writers. `NativePushUpdateTest` retains its entire original SDK 3→4 path and arguments.
The shared `readNativeDeliveryTargets` reader uses the
public typed own-provider producer from `NativeTypedConfigTest` and the existing complete-eight
`readNativeSelections` chain. `discoverDeliveryTargets` validates system IDs against actual
controller row IDs, returned slot/resource domains, owned providers and configured types;
null upper selections and enabled states remain explicit. See
[mapping and recovery limits](../apps/wear_android/README.md#guarded-normal-datasource-observations).
The target's ordinary UID must acquire the public SDK manager and receive typed configs;
availability, acquisition, callback/result/error and caller/resource/runtime/full-eight brackets
are recorded separately in private `files/native_read/requester-*/receipt.json`. Own-provider
metadata is not all-provider selection evidence. Missing, duplicate, foreign, changed or unresolved
associations stay Pending; do not guess IDs, use numerical/provider-only joins, synthesize
records, use cached data/default policy, select providers or grant permission to proceed.
No client acquisition is required. New resource diagnostics distinguish resource-package and
runtime-package reads without relabeling prior ambiguous `beforeResource` or uninvoked client
acquisition as a proven denial or package-visibility cause.

For an active Push target, the reader reuses actual caller-owned inventory before and after
the typed observation. It retains exact package/version/manager-slot/active/configuration
scope, checks the version against the installed resource and requires the freshly observed
slot's `expectedSlotSha256`. A Legacy-only read never acquires Push inventory or requires
Push ownership. Missing ownership on a Push target stays Pending without installation,
manager mutation or activation. `NativeDeliveryMapping.scopeSha256` binds current caller,
resource/runtime, System, full-eight native and applicable Push evidence to the first-frame
and restoration receipts; read evidence grants no publication, request or direct-data authority.

Freshly populate the named variables from independent current installed/active observations.
Do not reuse a historical manager-witness host hash. The command shape for the single
first-frame Legacy probe is:

```sh
adb -s "$WEAR_SERIAL" shell am instrument -w -r \
  -e class app.wardpulse.wear.nativeintegration.NativeDatasourceTransitionTest#probeDelivery \
  -e wardpulseNativeIntegration normal-delivery \
  -e expectedAvd "$NATIVE_AVD" -e expectedFingerprintSha256 "$NATIVE_FINGERPRINT_SHA256" \
  -e expectedCallerUid "$NATIVE_CALLER_UID" -e expectedHostVersionCode "$NATIVE_HOST_VERSION_CODE" \
  -e expectedHostApkSha256 "$NATIVE_HOST_SHA256" -e expectedHostSignerSha256 "$NATIVE_HOST_SIGNER_SHA256" \
  -e expectedResourceApkSha256 "$NATIVE_RESOURCE_SHA256" -e expectedResourceSignerSha256 "$NATIVE_RESOURCE_SIGNER_SHA256" \
  -e expectedRuntimeApkSha256 "$NATIVE_RUNTIME_SHA256" -e expectedRuntimeSignerSha256 "$NATIVE_RUNTIME_SIGNER_SHA256" \
  -e expectedRuntime "$NATIVE_RUNTIME" -e expectedResourcePackage "$NATIVE_RESOURCE_PACKAGE" \
  -e expectedInstanceSha256 "$NATIVE_INSTANCE_SHA256" -e expectedConfigurationSha256 "$NATIVE_CONFIG_SHA256" \
  app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner
```

For an already-active owned Push resource, use its actual resource identity and add
`-e expectedSlotSha256 "$NATIVE_SLOT_SHA256"`, freshly obtained from its caller-owned
inventory. Do not infer the manager slot from native, resource or requester IDs.

Inspect the original private `files/native_datasource/probe/first.png` before batching. Require
a complete unobscured native frame; an overlay is not accepted evidence. Record its SHA-256.
HOST must establish quiet summary writers and quiet/unpaired transport, record the original
bridge/peer configuration, and restore it after reconciliation. Absence of connected nodes or
a running listener alone cannot prove that no producer has future work. Do not disable the
listener, freeze live preferences, clear state or overwrite a newer publication to create
these preconditions. If quiet ownership cannot be established, leave the mutation route Pending.

For one `observeDelivery` invocation, retain the same identity arguments, change only the
explicit method and add all these `-e` strings:

| Argument | Required value |
| --- | --- |
| `deliveryScenario` | One of `normal`, `delayed`, `obsolete`, `recovery` |
| `authorizedOperation` | `observeDelivery:<deliveryScenario>`, explicitly authorizing this exact scenario's publications, bounded requests and recovery |
| `quietWriters` | `confirmed-unpaired`, after establishing the HOST precondition |
| `firstFrameReview` | `complete-unobscured`, after inspecting this probe's original |
| `expectedReviewedFrameSha256` | SHA-256 of that exact private original PNG |
| `priorDeliveryRestorationReview`, `expectedPriorDeliveryRestorationSha256` | After an earlier case: `complete` and the exact prior receipt hash after its separate effective-restoration review |

Neither the probe receipt nor inventory/peer reads authorize these writes or establish quiet
writers. The reviewed first original must match the fresh full-scope hash. One method runs
one bounded scenario; its private directory prevents replay. The normal case
publishes a sanitized pair through `WatchSummaryStore.saveEncoded` and requests the selected
system IDs. Delayed stages withhold extra requests until after the main observation; obsolete
removes secondary mains/extras, and recovery restores the pair. Inspect every original
requested/bounded frame and actual effective data. Requested updates, accepted application
state, a runtime accessibility event, cached native data and effective rendering are separate
evidence. No callback provenance or transition PASS follows from request return, event arrival,
event timeout or the final frame. Redacted native fields can leave semantics unavailable.

`NativeSummaryLease` retains originals opaquely and restores only attributable owned data
after rechecking quiet writers. A newer publication is preserved and recorded privately;
unresolved interleaving/transport retains recovery material and stays Pending. There is no
cross-writer atomic compare-and-set guarantee. Requests and independent normal-data recovery
use only freshly validated intended targets with `requestUpdate`. Each provider group must be
durably armed before fresh mapping validation and dispatch; failed persistence prevents dispatch.
Recovery attempts independent groups even if one fails, preserving newer producer data.
Unresolved mapping or uncertain dispatch stays Pending without stale-ID reuse, blanket requests
or retries. A durable latest-case fence requires the prior later-restoration receipt and explicit
HOST effective-recovery review before another scenario; no scenario can be replayed.
The immediate frame is diagnostic. After actual native
settlement, select `observeRestoration` once with the same identity arguments plus
`deliveryScenario`; it records a separate later original and newer-write status without
publishing or restoring a snapshot. Verify actual restored normal delivery/rendering, retained
instance/bindings/upper choices/consent/settings/time/font/ambient and the original HOST bridge
state; reconcile newer data instead of forcing the old digest. Keep `.bin` originals,
reconciliation bytes, raw records and frames app-private until recovery/review is resolved.

`NativeDatasourceGuardTest` has two separately selectable private mapping/cleanup cases.
The three transition methods and two guard cases are annotation-excluded from the default
40. Neither source completion nor a successful instrumentation exit closes unavailable
provenance, unseen transitions or effective-restoration acceptance. All native outcomes remain
Pending until ordered HOST execution and inspection. Retire the instrumentation's single
UiAutomation owner before another native/hierarchy owner starts.

#### Independent client metadata observation

For the independent read, select exactly
`app.wardpulse.wear.nativeintegration.NativeClientMetadataTest#observeClientMetadata`
on `app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner`, with
`wardpulseNativeIntegration=client-metadata`. The isolated runner excludes it. This is a later
HOST observation after whole Runner DONE, owned-process retirement, any owning-CLI exit and
fresh separate public idle, with fresh runtime identity/custody and reviewed test-only provisioning.
No phone action or target installation to manufacture capability is authorized. Surface any
genuine target dependency for admission rather than relaxing guards.

The read checks current facts using `NativeReadAdmission` in
[NativeReadObservation.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeReadObservation.kt),
without the historical update journal, requester mappings or quiet-bridge admission. Preserve
the installed Round Wear4/asset3/Push4 identity separately from Source/built Push5. Legacy-only
Square does not need fabricated Push ownership/history. Supply independently observed values:

| Arguments | Current evidence |
| --- | --- |
| `expectedAvd`, `expectedFingerprintSha256` | Canonical emulator and exact current system image |
| `expectedCallerUid`, `expectedHostVersionCode` | Actual target/provider UID and installed Wear code, without assuming code 4 identifies the APK |
| `expectedHostApkSha256`, `expectedHostSignerSha256` | Current target APK and signer before and after test-only provisioning |
| `expectedResourcePackage`, `expectedResourceApkSha256`, `expectedResourceSignerSha256` | Actually active WFF resource package/APK/signer, independent of opaque instance identity |
| `expectedRuntime`, `expectedRuntimeApkSha256`, `expectedRuntimeSignerSha256` | Active runtime class suffix and installed runtime APK/signer |
| `expectedInstanceSha256` | Current opaque native instance hash, not a WFF resource WatchFaceId or SDK manager slot |
| `clientArtifactReview` | `resolved-1.2.1`, after actual resolved AAR/graph review |
| `expectedClientArtifactSha256`, `expectedClientGraphSha256` | Exact resolved client 1.2.1 AAR and retained dependency-graph receipt hashes; caller assertions alone prove no provenance |

Use the stock invocation shape above with the exact class/method, `client-metadata` opt-in and
all these arguments expanded. No candidate flags, manager-witness review, asset-3 hash,
Push4 hash, requester IDs or restoration receipt is an input to this read. Actual inaccessible
APK/service/permission/instance evidence remains an explicit outcome, without grants or fallbacks.

Inspect private `files/native_read/client-*/receipt.json`. `operations` distinguishes uninvoked,
unsupported, null/empty, denied/inaccessible, timeout, ambiguous/domain-unresolved and acquired
results. `clientSlots` records actual client keys/enabled states/supported types before matching;
different numbers from native slots are retained. `beforeFace`/`afterFace`, caller identities and
resource/runtime identities bracket the observation; raw configuration hashes are diagnostic,
not an invented selected-provider producer. Missing/changed evidence leaves association unresolved
while preserving returned metadata. No data, rendering, restoration or message call is made.

The read-only receipt kind cannot authorize `observeOverride`. The shared acquisition custody
in `files/native_client/acquisition/` fences both old and new client owners. A five-second
factory deadline and successful binding cleanup do not release an unreturned remote reference;
synchronous calls must return, and failed/unresolved custody requires HOST reconciliation before
another owner. Keep cleanup failures separate from acquisition outcomes and retain evidence.
The five new synthetic guard cases require later actual HOST execution; source review is not
runtime acceptance, restoration proof or #12 closure. The original historical SDK3→4 admission,
journal and settled witness remain unchanged.

#### Typed own-provider config observation

Select exactly
`app.wardpulse.wear.nativeintegration.NativeTypedConfigTest#observeActiveComplicationConfigs`
on `app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner`, with
`wardpulseNativeIntegration=typed-configs`. The isolated runner excludes it. Use the stock
invocation shape above and the independent-read current caller arguments: `expectedAvd`,
`expectedFingerprintSha256`, `expectedCallerUid`, `expectedHostVersionCode`,
`expectedHostApkSha256` and `expectedHostSignerSha256`. Actual process/target/package/signer
checks precede public SDK acquisition; no shell UID is adopted for that call. Historical Push,
requester, client-artifact and quiet-bridge inputs are not required.

For optional active-face bracketing, additionally supply the independently observed current
`expectedResourcePackage`, `expectedResourceApkSha256`, `expectedResourceSignerSha256`,
`expectedRuntime`, `expectedRuntimeApkSha256`, `expectedRuntimeSignerSha256` and
`expectedInstanceSha256` arguments described above. Missing/inaccessible/changed bracket evidence
does not suppress own-provider metadata and cannot authorize a join. Preserve raw configs and
inspect each operation's invocation, target, returned domain and outcome rather than treating an
instrumentation exit as complete acceptance.

[NativeTypedConfigTest.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeTypedConfigTest.kt)
checks public Wear SDK 35.1 availability (`WEAR_VIC_1`), acquires `ComplicationsManager` with the
actual target context and calls `getActiveComplicationConfigsAsync`. Existing platform
`useLibrary("wear-sdk")` compile wiring supplies the public types absent from the prior test
compiler classpath; versions and the existing required-library contract are unchanged. Class
loading, availability and manager acquisition each still need runtime evidence. No reflection,
hidden API, new Maven dependency, grant or fallback is used.

Inspect fresh private `files/native_read/typed-*/receipt.json` for actual provider/system `id`,
`watchFaceSlotId`, provider component, resource `WatchFaceId` package/null-or-present class and
data type. Resource identity is separate from native opaque instance identity. Neither equal
numbers nor offsets, modulo, ordering, provider-only or stale/default policy establish joins
with generator/native/flat-row/client/SDK Push slot domains. `activeFaceAssociation` remains
`ambiguous/domain-unresolved`, including with stable brackets, and read-only receipts cannot
authorize mutations. The five-second callback wait starts after synchronous invocation returns;
late/duplicate completions cannot change a terminal receipt, but no platform retirement is inferred.

The five synthetic `NativeTypedConfigGuardTest` cases may later be selected explicitly by class
on the stock runner, without querying SDK/live state. They test callbacks and records, not an OS
producer. Actual execution/compilation and runtime capability remain pending HOST evidence,
after whole Runner DONE, all owned-process retirement, any owning-CLI exit and fresh separate
public idle. Before watch actions, freshly establish exact runtime identity/custody and reviewed
test-only provisioning. No phone action, target installation to manufacture access, historical
replay or state normalization is authorized. Preserve installed Round Wear4/asset3/Push4 separately
from Source/built Push5 and surface genuine target dependencies. Broader native/restoration/
artifact/compatibility/public acceptance gaps and whole-#12 closure remain pending.

#### Owned Push inventory and connected peers

These are separate later HOST observations on the stock
`app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner` entry. Select exactly one method
of `app.wardpulse.wear.nativeintegration.NativeInventoryObservationTest`:

| Method | `wardpulseNativeIntegration` | Private receipt |
| --- | --- | --- |
| `observeOwnedPushInventory` | `owned-push` | `files/native_read/owned-push-*/receipt.json` |
| `observeConnectedPeers` | `connected-peers` | `files/native_read/connected-peers-*/receipt.json` |

Use the stock invocation shape in [Guarded Push witness](#guarded-push-witness), substituting
the exact class/method and opt-in above. Supply only the independent current caller arguments:
`expectedAvd`, `expectedFingerprintSha256`, `expectedCallerUid`, `expectedHostVersionCode`,
`expectedHostApkSha256` and `expectedHostSignerSha256`. Neither route adopts shell authority
for its API call or requires the historical version-3 probe, journal, bundle, active-face/
resource/instance join, requester mapping or quiet-bridge inputs. The isolated runner excludes
both methods. Never run default discovery on the stock runner.

[NativeInventoryObservationTest.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeInventoryObservationTest.kt)
uses the existing Push wrapper's support/list APIs. Inspect actual caller-owned package/version/
manager-slot rows, remaining capacity, validation outcomes and the second inventory comparison.
Only a returned owned WardPulse Push package permits its `isActive` read. An absent package
leaves active status uninvoked; it is not a measured `false`. Active status and manager slots
do not establish a native-instance or complication-slot join. Raw invalid/changed inventory
remains retained with unresolved authority. Push reads use five-second cooperative deadlines.

The peer route directly awaits `NodeClient.connectedNodes` for at most five seconds after
synchronous task acquisition returns, then records remote ID/display name/nearby fields.
It never calls `requestRefresh` or a message client. Late completion cannot rewrite a terminal
receipt; no remote-retirement claim follows. Null, empty, denied/inaccessible, unsupported,
timeout and ambiguous/domain-unresolved outcomes remain distinct from uninvoked/successful
reads. Empty peers prove neither quiet writers nor lack of queued/local work, and GMS
connection-category flags are not peer results. Both routes repeat current caller identity.
Receipts are private read-only evidence and cannot satisfy override admission.

The seven synthetic `NativeInventoryGuardTest` cases can later be explicitly selected by class
on the stock runner; they do not access the SDK, peers or normal stores. Actual guard execution,
complete `just check-wear`, artifact/graph renewal and applicable RED→GREEN remain HOST work
after whole Runner DONE, all owned-process retirement, any owning-CLI exit and fresh separate
public idle. Watch observations additionally require fresh exact runtime identity/custody,
reviewed test-only provisioning and cleanup/recovery. Expose a genuine target dependency;
do not replace a target to manufacture access. No phone action is authorized. Keep installed
Round Wear4/asset3/Push4 separate from Source/built Push5; Legacy-only Square needs no invented
Push history. Preserve the historical SDK3→4 journal/settled witness and strict mutation guards.
Malformed/delayed/missing-main native, restoration, comprehensive artifact/compatibility and
healthy public acceptance remain pending; no universal PASS, physical-device or #12 closure follows.

#### Guarded complication client probe

Use this later HOST route only after whole execution DONE, all owned-process retirement and
separate fresh public idle, with separately reviewed compilation/provisioning as described
for current datasource observations. Preserve original targets; this route cannot authorize
early installation. Resolve and checksum the exact test-only client 1.2.1 artifact first,
including the warm/empty-cache/reuse proof above. No permission grant, instance creation,
activation, service-policy bypass or hidden state normalization is permitted.

The pinned 1.2.1 rendering API declares `WatchFaceLayer` in `androidx.wear.watchface.style`.
`NativeComplicationOverrideTest` uses that namespace without changing rendering parameters
or dependency versions. The recorded unresolved-import Kotlin failure did not install a target
or establish unavailable native capability. Corrected compilation, complete build checks and
actual client access remain separate Pending HOST evidence.

Select exactly one `NativeComplicationOverrideTest` method on the stock runner with
`wardpulseNativeIntegration=client-probe`. The three guarded native methods, seven synthetic
`NativeClientGuardTest` cases and independent metadata observation remain excluded by the
isolated runner; with the six typed-config and nine inventory cases the manual total is
thirty-eight and the default total stays 40. The guarded native methods require the same current
caller/resource/runtime/renderer and applicable owned-Push identity arguments as the
[datasource probe](#guarded-datasource-observations), plus
`clientArtifactReview=resolved-1.2.1` and `expectedClientArtifactSha256` from the actual resolved
AAR. Freshly observe identities; do not reuse the pre-replacement host hash. Current admission
requires no historical manager receipt, SDK-update entry resolution or old package cohort.
Separate client authorization, permission/capability checks and custody still guard binding
only the already-existing active instance; unavailable access remains Pending.

For `probeClient`, use the prior stock-runner command shape with these substitutions:

```sh
adb -s "$WEAR_SERIAL" shell am instrument -w -r \
  -e class app.wardpulse.wear.nativeintegration.NativeComplicationOverrideTest#probeClient \
  -e wardpulseNativeIntegration client-probe \
  -e clientArtifactReview resolved-1.2.1 \
  -e expectedClientArtifactSha256 "$CLIENT_AAR_SHA256" \
  ... \
  app.wardpulse.test/androidx.test.runner.AndroidJUnitRunner
```

The `...` denotes the mandatory identity arguments above; expand them before executing.
This is an invocation template, not an executable abbreviated command. Inspect private
`files/native_client/probe/first.png` for the first complete unobscured original and inspect
`probe/receipt.json` for actual API/service/permission/instance/slot access and cleanup. A
source signature, default datasource policy or caller-provided artifact hash proves none
of these capabilities. Unavailable/denied/unmapped capability stays Pending; do not override.

Only after a successful probe and supported recovery, select `observeOverride` once with:

| Additional argument | Required independent HOST observation/review |
| --- | --- |
| `clientProbeReview`, `normalRestorationReview` | Both `complete` |
| `expectedClientProbeSha256` | SHA-256 of the completed private probe receipt |
| `firstFrameReview` | `complete-unobscured` |
| `expectedReviewedFrameSha256` | SHA-256 of the inspected client probe original |
| `quietWriters` | `confirmed-unpaired`; preserve/restore the original HOST bridge state |
| `normalRestorationScenario` | The previously reviewed `normal`, `delayed`, `obsolete` or `recovery` datasource case |
| `expectedNormalRestorationReceiptSha256` | Exact completed datasource receipt after separate later restoration observation and effective-data review |
| `overrideMode` | `active` or `supplied-bitmap` |
| `overrideScenario` | One of the six cases in `nativeOverrideData` in [NativeClientProbe.kt](../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeClientProbe.kt) |
| `authorizedOperation` | `observeOverride:<overrideMode>:<overrideScenario>`, explicit authorization for this exact direct-data operation and bounded normal-data recovery; read receipts are insufficient |
| `priorClientRestorationReview`, `expectedPriorClientRestorationSha256` | After a previous armed client transport: `complete` and the exact prior case receipt hash following separate effective-restoration review |

The [component contract](../apps/wear_android/README.md#guarded-complication-client-probe)
defines cases, API/transport rejection, binding ownership and evidence limits. No argument
may supply guessed slot IDs, raw payloads, permission or a new instance. Each mode/scenario
is single-use, including failure; no retries, resets or deleted receipts to obtain a witness.
Keep `.bin` summary reference bytes, effective-data records and original frames private.
No summary is restored from those bytes: cleanup requests **current** normal producer data
only for freshly revalidated affected targets, using the shared typed mapping and durable
per-provider arming. Independent groups are attempted even after another failure; failed
persistence or unresolved mappings forbid dispatch. No blanket request, stale IDs or retry
can substitute. Legitimate newer publications and all existing choices/settings are preserved.

After that client owner retires and normal delivery separately settles, select
`observeRestoration` with the same mode/scenario and identity/artifact arguments. It captures
one later native original, checks client/binding cleanup and notes producer changes. Inspect
normal effective rendering and reconcile newer data, including bindings, upper choices,
consent, settings, time/font/ambient and original bridge state. Failed close or unreturned
interactive acquisition leaves resource ownership Pending; control unbind alone is not proof
that an unreturned remote reference released. Do not start another owner until reconciled.
The private latest-acquisition receipt guards subsequent cases; an earlier normal-delivery
receipt cannot substitute for reviewing this route's own effective restoration.
Supplied bitmaps cannot replace normal datasource/transition/true-ambient proof. No override,
restoration or visual PASS is promised; full native acceptance stays Pending.

#### Connected-suite retention policy

Both `just test-wear-device` and the connected suite inside `just test-phone-watch-sync`
require the shared Wear project policy in `apps/wear_android/gradle.properties`:
`android.injected.androidTest.leaveApksInstalledAfterRun` must be true. It suppresses
AGP's after-suite target/test/helper APK removal. Keep the complete suites; a post-test
reinstall or snapshot restore cannot substitute for preserving the installed app.

Before either route, use two separate built-in Gradle `:app:properties --property` reports
for that property and `android.experimental.testOptions.uninstallIncompatibleApks`, in
the same Wear project and invocation context. Require leave-installed true and
incompatible-uninstall false, or verified absence with AGP's default false. These are
selected project values, not an expanded AGP getter; bind them to the reviewed wiring
and defaults. Do not inject values or dump all properties. An unproved policy or
incompatible update is HOLD: no data clear, uninstall fallback, downgrade or fresh install.

UI-driven connected suites require the selected canonical targets to be awake, interactive
and unrestricted by keyguard. Record the prior power state and settings; an ordinary
`KEYCODE_WAKEUP` may wake a sleeping target, but verify the actual state before testing.
Restore temporary power-state or setting changes exactly after verification. No screen-timeout
change is required.

**UiAutomation ownership.** Keep one automation owner per selected target while a
connected instrumentation suite runs. Do not concurrently invoke `uiautomator dump`
or another consumer that registers a separate UiAutomation service. Observe through
noncompeting `screencap`, read-only `dumpsys`, or the existing instrumentation's own
outputs; defer hierarchy dumps until that instrumentation owner finishes.
Inspect the reported instrumentation test/run status and expected test counts before
declaring PASS. Interpret the invocation's output mode: formatted JUnit
`OK (...)`/`FAILURES!!!` summaries, or raw instrumentation status records with `-r`.
Confirm the selected cases and expected counts in either mode; do not require raw
`INSTRUMENTATION_STATUS_CODE: 0` in formatted output.
An ADB exit code of zero does not establish test success; an automation
registration abort supplies neither product-assertion evidence nor a verified frame.
Preserve earlier RED evidence and distinguish such an invocation failure from it.
Before recording a copied native artifact as present, verify its actual format and content:
a decodable PNG for an image, or the expected case/metric records for text. An ADB transfer's
exit code, destination filename or nonempty file alone proves none of this. Command
diagnostics and absent conditional outputs remain missing evidence; preserve the original
receipt and record the correction rather than accepting diagnostic text as an artifact.

Prove scoped before/after continuity of target UID, APK identity, saved-summary digest,
logical consent and verifier/debug-app/wait-for-debugger settings alongside work and pairing.
A compatible build can change APK bytes; a legitimate fresh publication can change the
summary digest. Correlate changes with the gate boundaries. Logical consent does not require
identical preference-file presence or bytes. The keep-installed policy and test counts alone
prove none of this. See [Phone-to-Watch Acceptance](../tools/test-phone-watch-sync/README.md).

Run the Wear OS acceptance checks with one canonical Wear AVD active:

```sh
just check-wear
just test-wear-device
just run-wear
```

Build and install the watch face with one canonical Wear AVD active:

```sh
just check-watchface
ANDROID_SERIAL="$WEAR_SERIAL" just run-watchface
```

For an initial paired environment only:

```sh
just prepare-phone-watch-sync
```

Follow **Pairing the canonical phone and Wear AVDs** for Studio and ADB consent. Do not
prepare, recreate/reset devices or re-pair an existing pair to make verification pass;
after a restart, restore the transient bridge instead.

Run the complete paired phone-to-watch gate:

```sh
just test-phone-watch-sync
```

The gate proves live roles and canonical AVD names, not emulator ports. Set `PHONE_SERIAL`
and `WEAR_SERIAL` explicitly when additional devices are online. Its fixed metadata reader
requires existing `javac` 21, API36 `android.jar`, Build Tools 36 `d8`/`aapt2` and supported
`run-as`/`app_process` execution; verification installs no SDK or SQLite dependency.

The complete recipe includes current builds, full Wear instrumentation and both preserving
updates; fresh phone publication and a distinct Wear callback; actual phone separation,
old Wear process death and a new process; ten further seconds of quiet with stable saved
summary evidence; and logical/native scheduled-work reconciliation. Matching data, command
success, old receipts, Source review or a partial suite cannot replace the full gate.
Unknown identity, missing metadata or lost observation is HOLD.

Preflight uses bounded fixed-query metadata for the installed WorkManager 2.11.2/schema 24
binding, SQLite version/source identity and a consistent read-only WAL snapshot. It observes
sanitized lifecycle/publication events and job identity/specification changes. The reader
does not initialize app/Room/WorkManager, export database payloads, read credentials or dump
preferences; saved-summary contents flow only through the hash pipeline. Read-only does
not promise zero filesystem effects: reviewed automatic SHM coordination is distinct from
forbidden deliberate mutation, repair, checkpoint or journal conversion.

On 2026-10-18, the complete ordinary paired gate passed on the canonical phone and round
Wear AVD with the targets awake. All 16 connected tests and 138 Gradle tasks passed in
46 seconds. Both preserving updates, all logical/native work checkpoints, fresh publication
and Wear delivery, actual phone separation, Wear old-process death/new process and at least
ten further seconds of quiet with stable summary hash/metadata passed; owned-reader cleanup
also completed. Separate complete round and square connected routes each passed all 16 tests
and 138 tasks, in 21 and 22 seconds respectively. Full `just check-phone`, `just check-wear`,
`just check-designs` and `just check-docs` also passed.

The installed WorkManager 2.11.2/schema 24/SQLite 3.44.3 WAL binding and current Java/DEX
correspondence were verified. Thirteen canonical reader cycles completed, including the
first ordinary observer after UID-wide phone-app absence and normal transaction end/close.
Two pairs of verified coexisting read-only observers received concurrent GO invocations;
all four completed their bounded DB results, END, exit and retirement. This is bounded
concurrent-invocation evidence alongside the reviewed Source/compiled nondeleting-handler
proof. Post-GO process co-liveness, overlapping internal SQLite transactions and contention
were not observed; unexecuted sidecar, corruption and internal SHM branches are not claimed
as dynamic passes. See `WorkSnapshot.snapshot` and `WorkSnapshot.main` in
`tools/test-phone-watch-sync/WorkSnapshot.java` and the acceptance README's
[Dated status](../tools/test-phone-watch-sync/README.md#dated-status).

Actual native fit measurements completed all ten approved scenes on 384×384 round and
360×360 notround targets, including the longest Sonnet title and three credited rows,
with per-scene conditional summary restoration in fresh processes. After returning to the
canonical Round, current pairing, fresh delivery, retained scheduled work, logical consent
and app settings were verified, and the latest real summary was retained. Temporary Round
wake-up was reversed to a verified noninteractive state without persistent setting changes;
this is scoped logical restoration evidence. These are scoped emulator verification results.

The historical force-stop result is not current preservation evidence. Follow
[Phone-to-Watch Acceptance](../tools/test-phone-watch-sync/README.md) for the complete
prerequisites, privacy limits and required evidence.

Do not hardcode `emulator-5554` in project automation; resolve the active device through
`flutter devices` or `adb devices` because the emulator port can change.

## Later-Phase Gaps

The Android toolchain is complete through the Phase 7 implementation. Android Studio **Quail 2 | 2026.1.2**,
the Play Store phone image, and the canonical `wardpulse_phone_play_api36` AVD completed the
emulator-to-emulator pairing check. The canonical Wear AVD also passed WFF install, render,
tap-to-open, and ambient acceptance on the shared AGP 9.3 baseline. Phase 7 needs no
additional Android host package. Codex acceptance uses the phone's browser and secure storage;
Node.js 24 remains a documentation and design-tooling dependency only.

## Updating The Baseline

Updates are explicit project changes, not silent local drift:

```sh
flutter channel stable
flutter upgrade
android --sdk="$ANDROID_HOME" sdk update
```

After an update:

1. Record new versions in this document.
2. Run `flutter doctor -v`, core checks, Flutter analysis, and Flutter tests.
3. Verify the phone emulator and debug APK.
4. Update CI pins or generated Gradle files when the change affects reproducibility.

## Official References

- [Flutter SDK release index](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
- [Flutter manual installation](https://docs.flutter.dev/install/manual)
- [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup)
- [Android Studio stable releases](https://developer.android.com/studio/releases)
- [Android CLI](https://developer.android.com/tools/agents/android-cli)
- [Android `sdkmanager` bootstrap](https://developer.android.com/tools/sdkmanager)
- [Android Emulator controls](https://developer.android.com/studio/run/emulator)
- [Android Emulator acceleration](https://developer.android.com/studio/run/emulator-acceleration)
- [Android Emulator snapshots and management](https://developer.android.com/studio/run/emulator-snapshots)
- [Android SDK platform releases](https://developer.android.com/tools/releases/platforms)
- [Android Gradle Plugin 9.3](https://developer.android.com/build/releases/agp-9-3-0-release-notes)
- [Compose BOM](https://developer.android.com/develop/ui/compose/bom)
- [Compose for Wear OS releases](https://developer.android.com/jetpack/androidx/releases/wear-compose)
- [Wear OS app packaging](https://developer.android.com/training/wearables/apps/packaging)
- [Wear OS Data Layer overview](https://developer.android.com/training/wearables/data/overview)
- [Sync data with Data Layer](https://developer.android.com/training/wearables/data/sync)
- [Connect a watch to a phone](https://developer.android.com/training/wearables/get-started/connect-phone)
- [Watch Face Format overview](https://developer.android.com/training/wearables/wff)
- [Watch Face Format setup](https://developer.android.com/training/wearables/wff/setup)
- [Build a Watch Face Format package](https://developer.android.com/training/wearables/wff/build)
- [Watch Face Format ambient mode](https://developer.android.com/training/wearables/wff/ambient)
- [Official WFF validator and schema](https://github.com/google/watchface)
- [Watch Face Push](https://developer.android.com/training/wearables/watch-face-push)
- [Push integration in a Wear app](https://developer.android.com/training/wearables/watch-face-push/wear-os-app)
- [AndroidX Watch Face Push releases](https://developer.android.com/jetpack/androidx/releases/wear-watchfacepush)
- [WatchFacePushManagerFactory](https://developer.android.com/reference/androidx/wear/watchfacepush/WatchFacePushManagerFactory)
- [ComplicationDataSourceService metadata](https://developer.android.com/reference/androidx/wear/watchface/complications/datasource/ComplicationDataSourceService)
- [Android NDK downloads](https://developer.android.com/ndk/downloads)
- [Rust Android platform support](https://doc.rust-lang.org/rustc/platform-support/android.html)
- [`cargo-ndk` releases](https://github.com/bbqsrc/cargo-ndk/releases)
- [Dart `ffi` package](https://pub.dev/packages/ffi)
