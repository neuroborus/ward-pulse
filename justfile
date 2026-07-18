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

gen-bindings:
    @echo "TODO: generate Dart/Kotlin/Swift bindings from core/ward-pulse-ffi."

run-phone:
    cd apps/phone_flutter && flutter run

run-wear:
    @echo "TODO: run the Wear OS app after Wear OS project files are added."

build-watchface:
    @echo "TODO: build the WFF package after WFF project files are added."

test-all: check-core check-phone
