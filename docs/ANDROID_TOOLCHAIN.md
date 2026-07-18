# Android Toolchain

This document is the operational source of truth for the WardPulse Android development
environment. It records the baseline through the Phase 5 implementation, canonical SDK
package names, local paths, verification commands, and tooling that is intentionally not
installed yet.

Last verified: **2026-07-18** on TUXEDO OS 24.04.4 LTS, x86_64.

## Current Readiness

The command-line toolchain required through the local **Phase 5 — phone-to-watch sync**
build and test gates is ready:

- Flutter detects the Android SDK and reports the Android toolchain as healthy.
- All Android SDK licenses are accepted.
- Android 16 / API 36 and Build Tools 36.0.0 are installed.
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
- Android SDK Platform 37.1 is installed for the Wear compile SDK while target SDK remains
  API 36.
- The Wear OS 6.1 x86_64 system image and canonical round and square AVDs are installed.
- The Wear app passes lint, builds its debug and instrumentation APKs, runs on both AVD
  shapes, and passes its local-persistence tests on the round AVD.
- Phone and Wear builds use Wearable Data Layer `20.0.1`; the Wear listener validates the
  versioned summary before replacing locally persisted state.

The Phase 2 phone-dashboard, Phase 3 Rust-bridge, and Phase 4 Wear-app acceptance gates
passed on **2026-07-18**.

Phase 5 paired-device acceptance is pending. The installed `google_apis` phone image is
sufficient for normal phone development but not for Android Studio's Wear pairing flow;
that flow requires a Play Store phone image, documented below.

Chrome and Linux desktop warnings from `flutter doctor` are out of scope. WardPulse targets
Android phone, Wear OS, and Watch Face Format in the current product plan.

## Verified Versions

| Component | Verified version | Current role |
| --- | --- | --- |
| Flutter | 3.44.6, stable channel | Phase 2 phone UI |
| Dart | 3.12.2, bundled with Flutter | Phase 2 phone UI |
| Flutter DevTools | 2.57.0 | Flutter diagnostics |
| OpenJDK / `javac` | 21.0.11 | Android builds and SDK tools |
| Android SDK Command-line Tools | 20.0, bundle `14742923` | `sdkmanager` and `avdmanager` |
| Android SDK Platform | `platforms;android-36`, revision 2 | Compile SDK baseline |
| Android SDK Platform | `platforms;android-37.1`, revision 1 | Wear compile SDK |
| Android SDK Build Tools | `build-tools;36.0.0` | Android build baseline |
| Android SDK Platform Tools | 37.0.0 | `adb` |
| Android Emulator | 36.6.11.0, build 15507667 | Phone emulator |
| Android phone system image | `system-images;android-36;google_apis;x86_64`, revision 7 | Phone AVD |
| Android Wear system image | `system-images;android-36.1;android-wear-signed;x86_64`, revision 1 | Wear OS 6.1 AVDs |
| Gradle Wrapper | 9.1.0 | Flutter Android build |
| Android Gradle Plugin | 9.0.1 | Flutter Android runner |
| Kotlin Gradle Plugin | 2.3.20 | Flutter Android host activity |
| Wear Gradle Wrapper | 9.6.1 | Native Wear app build |
| Wear Android Gradle Plugin | 9.3.0 | Native Wear app build |
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
| Git | 2.43.0 | Source control and Flutter SDK support |

The Rust workspace declares Rust 1.75 as its minimum supported version. The newer local
toolchain must continue to pass the minimum-version CI job.

## Canonical Names And Paths

Use these names consistently in local commands and future automation:

```text
Flutter SDK:       $HOME/develop/flutter
Android SDK:       $HOME/Android/Sdk
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
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
```

Review and accept the Android licenses interactively:

```sh
sdkmanager --licenses
```

Install the pinned phone, bridge, and Wear packages:

```sh
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "platforms;android-36" \
  "platforms;android-37.1" \
  "build-tools;36.0.0" \
  "emulator" \
  "system-images;android-36;google_apis;x86_64" \
  "system-images;android-36.1;android-wear-signed;x86_64" \
  "ndk;28.2.13676358" \
  "cmake;3.22.1" \
  "ndk;29.0.14206865"
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
sdkmanager --sdk_root="$ANDROID_HOME" \
  "system-images;android-36;google_apis_playstore;x86_64"

printf 'no\n' | avdmanager create avd \
  --name wardpulse_phone_play_api36 \
  --package "system-images;android-36;google_apis_playstore;x86_64" \
  --device pixel_7 \
  --force
```

Start `wardpulse_phone_play_api36` and one canonical Wear AVD, then pair them with Android
Studio's Wear OS emulator pairing assistant. Both WardPulse APKs must use application ID
`app.wardpulse` and the same signing certificate; the Wear Kotlin namespace remains
`app.wardpulse.wear`.

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

The app compiles against Android SDK 37.1 but targets API 36 and runs on the Wear OS 6.1 /
API 36.1 image. Compile SDK and runtime system image versions are intentionally independent.

## Routine Verification

Verify installed versions and packages:

```sh
flutter --version
dart --version
java -version
rustc --version
cargo --version
sdkmanager --version
sdkmanager --sdk_root="$ANDROID_HOME" --list_installed
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
```

Run the phone Android acceptance checks:

```sh
just build-android-rust
cd apps/phone_flutter
flutter build apk --debug
flutter run
```

Run the Wear OS acceptance checks with one canonical Wear AVD active:

```sh
just check-wear
just test-wear-device
just run-wear
```

Do not hardcode `emulator-5554` in project automation; resolve the active device through
`flutter devices` or `adb devices` because the emulator port can change.

## Later-Phase Gaps

The command-line toolchain is complete for Phase 5 builds and local tests. Android Studio is
not installed and is optional for the verified CLI workflow, but its pairing assistant is
required for the Phase 5 emulator-to-emulator acceptance test. The stable IDE at the last
verification date is Android Studio **Quail 2 | 2026.1.2**, which supports the Wear project's
AGP 9.3 baseline.

The remaining Android roadmap is not tool-complete yet. Install or select these only when
their phase begins:

### Phase 6 — Watch Face Format

- No additional host package is required yet.
- WFF build and validation versions must be chosen with the generated Gradle project during
  Phase 6.

## Updating The Baseline

Updates are explicit project changes, not silent local drift:

```sh
flutter channel stable
flutter upgrade
sdkmanager --update
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
- [Android `sdkmanager`](https://developer.android.com/tools/sdkmanager)
- [Android Emulator acceleration](https://developer.android.com/studio/run/emulator-acceleration)
- [Android SDK platform releases](https://developer.android.com/tools/releases/platforms)
- [Android Gradle Plugin 9.3](https://developer.android.com/build/releases/agp-9-3-0-release-notes)
- [Compose BOM](https://developer.android.com/develop/ui/compose/bom)
- [Compose for Wear OS releases](https://developer.android.com/jetpack/androidx/releases/wear-compose)
- [Wear OS app packaging](https://developer.android.com/training/wearables/apps/packaging)
- [Wear OS Data Layer overview](https://developer.android.com/training/wearables/data/overview)
- [Sync data with Data Layer](https://developer.android.com/training/wearables/data/sync)
- [Connect a watch to a phone](https://developer.android.com/training/wearables/get-started/connect-phone)
- [Android NDK downloads](https://developer.android.com/ndk/downloads)
- [Rust Android platform support](https://doc.rust-lang.org/rustc/platform-support/android.html)
- [`cargo-ndk` releases](https://github.com/bbqsrc/cargo-ndk/releases)
- [Dart `ffi` package](https://pub.dev/packages/ffi)
