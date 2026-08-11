set shell := ["bash", "-cu"]

default:
    just --list

fmt-core:
    cd core && cargo fmt --all

lint-core:
    cd core && cargo clippy --workspace --all-targets -- -D warnings

test-core:
    cd core && cargo test --workspace

# Rustdoc reads only the items it documents, hence --document-private-items.
# Fails on a broken intra-doc link; nothing else in the repo reports one.
doc-core:
    cd core && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items

# Dart formatting for the phone shell and the bindings package it consumes.
fmt-phone:
    cd apps/phone_flutter && dart format lib test
    cd bindings/dart && dart format lib

lint-phone:
    cd apps/phone_flutter && flutter analyze

test-phone:
    cd apps/phone_flutter && flutter test

check-phone:
    cd apps/phone_flutter && dart format --output=none --set-exit-if-changed lib test
    cd bindings/dart && dart format --output=none --set-exit-if-changed lib
    just lint-phone
    just test-phone

check-core: validate-fixtures
    cd core && cargo fmt --all -- --check
    cd core && cargo clippy --workspace --all-targets -- -D warnings
    cd core && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items
    cd core && cargo test --workspace

snapshot-core:
    @cd core && cargo run --quiet -p ward-pulse-cli

validate-fixtures:
    python3 tools/validate-fixtures/validate_json.py

docs-dev:
    npm run docs:dev

check-docs:
    npm run docs:build

export-design source output format="svg" scale="1":
    npm run design:export -- "{{source}}" --format "{{format}}" --scale "{{scale}}" --output "{{output}}"

# Canonical vectors from tools/render-brand-icons.mjs (metal + mono).
# Rasterizes launcher / watch-face PNGs with ImageMagick. OpenPencil .fig is optional.
export-icons:
    tools/export-icons.sh

build-android-rust:
    tools/build-android-rust/build.sh

run-phone: build-android-rust
    cd apps/phone_flutter && flutter run

check-wear:
    cd apps/wear_android && ./gradlew --no-daemon lintDebug testDebugUnitTest assembleDebug assembleDebugAndroidTest

validate-watchface:
    tools/validate-watchface/validate.sh

# Writes watchface.xml and the ring-type drawables; edit the generator, not its output.
# Needs ImageMagick `convert` for the drawables, as export-icons does.
render-watchface:
    node tools/render-watchface.mjs

check-watchface: validate-watchface
    node tools/render-watchface.mjs --check
    cd apps/watchface_wff && ./gradlew --no-daemon lintDebug assembleDebug bundleDebug

test-wear-device:
    cd apps/wear_android && ./gradlew --no-daemon connectedDebugAndroidTest

prepare-phone-watch-sync:
    tools/test-phone-watch-sync/run.sh prepare

test-phone-watch-sync:
    tools/test-phone-watch-sync/run.sh verify

build-wear:
    cd apps/wear_android && ./gradlew --no-daemon assembleDebug

# The Wear app shares `app.wardpulse` with the phone shell, so an install that
# reaches a paired phone replaces the dashboard with the watch UI. Naming the
# watch scopes both steps: Gradle's install task filters devices by ANDROID_SERIAL.
run-wear:
    @test -n "${ANDROID_SERIAL:-}" || { echo "Set ANDROID_SERIAL to a Wear device serial."; exit 1; }
    cd apps/wear_android && ./gradlew --no-daemon installDebug
    adb -s "$ANDROID_SERIAL" shell am start -n app.wardpulse/app.wardpulse.wear.MainActivity

build-watchface:
    cd apps/watchface_wff && ./gradlew --no-daemon assembleDebug bundleDebug

run-watchface:
    @test -n "${ANDROID_SERIAL:-}" || { echo "Set ANDROID_SERIAL to a Wear device serial."; exit 1; }
    cd apps/watchface_wff && ./gradlew --no-daemon installDebug
    adb -s "$ANDROID_SERIAL" shell am broadcast -a com.google.android.wearable.app.DEBUG_SURFACE --es operation set-watchface --es watchFaceId app.wardpulse.watchface

test-all: check-core check-phone check-wear check-watchface check-docs
