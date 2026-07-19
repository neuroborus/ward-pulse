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
- The paired Play Store phone and round Wear AVD deliver the canonical summary; it remains
  unchanged after the phone app is force-stopped and the Wear app is restarted.
- The official WFF validator accepts the declarative watch face, and the package builds as
  APK/AAB without dex files.
- The watch face installs and renders on the round Wear AVD; tap-to-open and ambient mode
  pass emulator acceptance.

The Phase 2 phone-dashboard, Phase 3 Rust-bridge, and Phase 4 Wear-app acceptance gates
passed on **2026-07-18**. Phase 5 paired-device and Phase 6 WFF acceptance passed on
**2026-07-19**.

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
| Android phone system image | `system-images;android-36;google_apis;x86_64`, revision 7 | Phone AVD |
| Android phone Play Store image | `system-images;android-36;google_apis_playstore;x86_64`, revision 7 | Paired phone AVD |
| Android Wear system image | `system-images;android-36.1;android-wear-signed;x86_64`, revision 1 | Wear OS 6.1 AVDs |
| Gradle Wrapper | 9.1.0 | Flutter Android build |
| Android Gradle Plugin | 9.0.1 | Flutter Android runner |
| Kotlin Gradle Plugin | 2.3.20 | Flutter Android host activity |
| Wear Gradle Wrapper | 9.6.1 | Native Wear app build |
| Wear Android Gradle Plugin | 9.3.0 | Native Wear app build |
| WFF validator | 1.7.0 | WFF v1 schema validation |
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
Phone AVD:         wardpulse_phone_api36
Phone platform:    android-36
Phone system image system-images;android-36;google_apis;x86_64
Paired phone AVD:  wardpulse_phone_play_api36
Paired phone image system-images;android-36;google_apis_playstore;x86_64
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

Create the canonical phone AVD:

```sh
avdmanager create avd \
  --name wardpulse_phone_api36 \
  --package "system-images;android-36;google_apis;x86_64" \
  --force
```

Accept the default `no` answer when asked whether to create a custom hardware profile.

List and start it with:

```sh
emulator -list-avds
emulator -accel-check
emulator @wardpulse_phone_api36
```

Verify the running device from another shell:

```sh
adb devices -l
flutter devices
```

The expected Flutter device is an Android x64 emulator running Android 16 / API 36.

### Phase 5 paired phone AVD

Wear Data Layer emulator pairing requires a phone image with the Play Store. Install the
image and create a separate AVD without replacing the canonical CLI phone AVD:

```sh
android --sdk="$ANDROID_HOME" sdk install \
  system-images/android-36/google_apis_playstore/x86_64

printf 'no\n' | avdmanager create avd \
  --name wardpulse_phone_play_api36 \
  --package "system-images;android-36;google_apis_playstore;x86_64" \
  --device pixel_7 \
  --force

# avdmanager may leave this disabled even for a Play Store image.
sed -i 's/^PlayStore.enabled=no$/PlayStore.enabled=yes/' \
  "$HOME/.android/avd/wardpulse_phone_play_api36.avd/config.ini"
```

Start `wardpulse_phone_play_api36` and one canonical Wear AVD, then pair them with Android
Studio's Wear OS emulator pairing assistant. Installing the Google Pixel Watch companion
from Play Store requires a Google account on the phone AVD; use a dedicated test account.
The companion's optional `Associate` action is not part of this acceptance flow and is not
required for Data Layer. Both WardPulse APKs must use application ID `app.wardpulse` and the
same signing certificate; the Wear Kotlin namespace remains `app.wardpulse.wear`.

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

The app compiles against Android SDK 37.1 but targets API 36 and runs on the Wear OS 6.1 /
API 36.1 image. Compile SDK and runtime system image versions are intentionally independent.

## Watch Face Format

The Phase 6 watch face is a separate resource-only package in `apps/watchface_wff/`:

| Setting | Value | Purpose |
| --- | --- | --- |
| Watch Face Format | version 1 | Digital time, ambient variants, and tap-to-open on Wear OS 4+ |
| Application ID | `app.wardpulse.watchface` | Independent watch face package |
| Minimum SDK | API 33 | Minimum runtime for WFF v1 |
| Compile SDK | Android SDK 37.1 | Shared Android build baseline |
| Target SDK | API 36 | Shared Android target baseline |
| Android Gradle Plugin | 9.3.0 | Shared Android build plugin |
| Gradle | 9.6.1 | Checked-in wrapper version |

No additional host package or runtime library is required. `just validate-watchface`
downloads the official validator 1.7.0 once from immutable GitHub asset `464497818`, checks
SHA-256 `3a10def0521ab97f41ab1b7e27a35649370af51580603b5bf656604d88f1aa29`, and caches it
under `${XDG_CACHE_HOME:-$HOME/.cache}/wardpulse/`. Validate, build, and lint locally with:

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

The preview image is a sanitized emulator capture. After visual changes, replace it with a
fresh interactive-mode capture from the canonical round Wear AVD.

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
cd apps/phone_flutter
flutter build apk --debug
flutter run
```

For Codex acceptance, open **Settings > Codex account**, start sign-in, open the external OpenAI
page, and enter the one-time code. Plan usage is enabled by default; purchased usage can be
enabled independently. The OAuth session stays in phone-secure storage and does not require a
Codex CLI, local server, or `adb reverse`.

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

Prepare and run the paired phone-to-watch acceptance check:

```sh
just prepare-phone-watch-sync
just test-phone-watch-sync
```

The preparation command is one-time; pairing still completes in Android Studio. The test
command discovers one online phone and one online Wear device without hardcoded emulator
ports. Set `PHONE_SERIAL` and `WEAR_SERIAL` explicitly when additional devices are online.

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
- [Android NDK downloads](https://developer.android.com/ndk/downloads)
- [Rust Android platform support](https://doc.rust-lang.org/rustc/platform-support/android.html)
- [`cargo-ndk` releases](https://github.com/bbqsrc/cargo-ndk/releases)
- [Dart `ffi` package](https://pub.dev/packages/ffi)
