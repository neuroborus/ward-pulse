# Android Toolchain

This document is the operational source of truth for the WardPulse Android development
environment. It records the Phase 2 baseline, canonical SDK package names, local paths,
verification commands, and later-phase tooling that is intentionally not installed yet.

Last verified: **2026-07-18** on TUXEDO OS 24.04.4 LTS, x86_64.

## Current Readiness

The command-line toolchain required for **Phase 2 — Flutter phone dashboard** is ready:

- Flutter detects the Android SDK and reports the Android toolchain as healthy.
- All Android SDK licenses are accepted.
- Android 16 / API 36 and Build Tools 36.0.0 are installed.
- The canonical phone AVD is installed, starts, and is detected by Flutter.
- `flutter analyze` passes for `apps/phone_flutter`.
- `flutter test` passes, including usage-history rendering and provider-detail navigation.
- `flutter build apk --debug` produces the WardPulse debug APK.
- The `app.wardpulse` runner starts on the canonical AVD and renders the dashboard,
  usage-history chart, provider list, and provider detail screen.

The Phase 2 phone-dashboard acceptance gate passed on **2026-07-18**. Phase 3 tooling is
still intentionally incomplete until the Rust-to-Flutter bridge approach is selected.

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
| Android SDK Build Tools | `build-tools;36.0.0` | Android build baseline |
| Android SDK Platform Tools | 37.0.0 | `adb` |
| Android Emulator | 36.6.11.0, build 15507667 | Phone emulator |
| Android phone system image | `system-images;android-36;google_apis;x86_64`, revision 7 | Phone AVD |
| Gradle Wrapper | 9.1.0 | Flutter Android build |
| Android Gradle Plugin | 9.0.1 | Flutter Android runner |
| Kotlin Gradle Plugin | 2.3.20 | Android host activity |
| Android NDK | `ndk;28.2.13676358` | Flutter Android debug build |
| Android NDK | `ndk;29.0.14206865` | Reserved for Phase 3 Rust bridge |
| Android SDK CMake | 3.22.1 | Flutter Android debug build |
| Host CMake | 3.31.6 | Available for later native build work |
| Rust | 1.96.0 | Domain core and future Android library builds |
| Cargo | 1.96.0 | Rust workspace |
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
Application ID:    app.wardpulse
Flutter NDK:       ndk;28.2.13676358
Rust bridge NDK:   ndk;29.0.14206865
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
a global Gradle distribution for project builds; let Flutter manage the generated Gradle
Wrapper.

## Reproducible Phase 2 Installation

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

Install the pinned Phase 2 packages and the Phase 3 NDK baseline:

```sh
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "emulator" \
  "system-images;android-36;google_apis;x86_64" \
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
cd apps/phone_flutter
flutter pub get
flutter analyze
flutter test
```

Run the Phase 2 Android acceptance checks:

```sh
flutter build apk --debug
flutter run
```

Do not hardcode `emulator-5554` in project automation; resolve the active device through
`flutter devices` or `adb devices` because the emulator port can change.

## Later-Phase Gaps

The full Android roadmap is not tool-complete yet. Install or select these only when their
phase begins:

### Phase 3 — Rust to Flutter bridge

- Android NDK r29 is installed.
- `cargo-ndk` is not installed or version-pinned yet.
- Android Rust targets are not installed yet.
- The binding generator is not selected yet; the plan permits UniFFI or a thin JSON bridge.

After the bridge approach and tool version are recorded, add the required Rust targets:

```sh
rustup target add \
  aarch64-linux-android \
  armv7-linux-androideabi \
  x86_64-linux-android
```

Do not install an unpinned `cargo-ndk` in project automation. Select a version when the
Phase 3 build script is implemented, then record it here and in CI.

### Phase 4 — Wear OS

- Android Studio is not currently installed. It is optional for Phase 2 command-line work,
  but should be installed before Compose for Wear OS development.
- No Wear OS system image or Wear AVD has been selected yet.
- The Wear Gradle project is still a repository placeholder.

The current stable IDE at the last verification date is Android Studio
**Quail 2 | 2026.1.2**. Re-check the stable release before Phase 4 instead of pinning a stale
IDE download in automation.

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
- [Android NDK downloads](https://developer.android.com/ndk/downloads)
