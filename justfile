set shell := ["bash", "-cu"]

default:
    just --list

fmt-core:
    cd core && cargo fmt --all

lint-core:
    cd core && cargo clippy --workspace --all-targets -- -D warnings

test-core:
    cd core && cargo test --workspace

lint-phone:
    cd apps/phone_flutter && flutter analyze

test-phone:
    cd apps/phone_flutter && flutter test

check-phone:
    just lint-phone
    just test-phone

check-core: validate-fixtures
    cd core && cargo fmt --all -- --check
    cd core && cargo clippy --workspace --all-targets -- -D warnings
    cd core && cargo test --workspace

snapshot-core:
    @cd core && cargo run --quiet -p ward-pulse-cli

validate-fixtures:
    python3 tools/validate-fixtures/validate_json.py

build-android-rust:
    tools/build-android-rust/build.sh

run-phone: build-android-rust
    cd apps/phone_flutter && flutter run

check-wear:
    cd apps/wear_android && ./gradlew --no-daemon lintDebug testDebugUnitTest assembleDebug assembleDebugAndroidTest

validate-watchface:
    tools/validate-watchface/validate.sh

check-watchface: validate-watchface
    cd apps/watchface_wff && ./gradlew --no-daemon lintDebug assembleDebug bundleDebug

test-wear-device:
    cd apps/wear_android && ./gradlew --no-daemon connectedDebugAndroidTest

prepare-phone-watch-sync:
    tools/test-phone-watch-sync/run.sh prepare

test-phone-watch-sync:
    tools/test-phone-watch-sync/run.sh verify

build-wear:
    cd apps/wear_android && ./gradlew --no-daemon assembleDebug

run-wear:
    cd apps/wear_android && ./gradlew --no-daemon installDebug
    adb shell am start -n app.wardpulse/app.wardpulse.wear.MainActivity

build-watchface:
    cd apps/watchface_wff && ./gradlew --no-daemon assembleDebug bundleDebug

run-watchface:
    @test -n "${ANDROID_SERIAL:-}" || { echo "Set ANDROID_SERIAL to a Wear device serial."; exit 1; }
    cd apps/watchface_wff && ./gradlew --no-daemon installDebug
    adb -s "$ANDROID_SERIAL" shell am broadcast -a com.google.android.wearable.app.DEBUG_SURFACE --es operation set-watchface --es watchFaceId app.wardpulse.watchface

test-all: check-core check-phone check-wear check-watchface
