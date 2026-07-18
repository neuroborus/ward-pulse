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

test-wear-device:
    cd apps/wear_android && ./gradlew --no-daemon connectedDebugAndroidTest

build-wear:
    cd apps/wear_android && ./gradlew --no-daemon assembleDebug

run-wear:
    cd apps/wear_android && ./gradlew --no-daemon installDebug
    adb shell am start -n app.wardpulse/app.wardpulse.wear.MainActivity

build-watchface:
    @echo "TODO: build the WFF package after WFF project files are added."

test-all: check-core check-phone check-wear
