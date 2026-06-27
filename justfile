set shell := ["bash", "-cu"]

default:
    just --list

fmt-core:
    cd core && cargo fmt --all

lint-core:
    cd core && cargo clippy --workspace --all-targets -- -D warnings

test-core:
    cd core && cargo test --workspace

check-core:
    cd core && cargo fmt --all -- --check
    cd core && cargo clippy --workspace --all-targets -- -D warnings
    cd core && cargo test --workspace

gen-bindings:
    @echo "TODO: generate Dart/Kotlin/Swift bindings from core/ward-pulse-ffi."

run-phone:
    @echo "TODO: run the Flutter phone app after apps/phone_flutter is generated."

run-wear:
    @echo "TODO: run the Wear OS app after apps/wear_android is generated."

build-watchface:
    @echo "TODO: build the WFF package after apps/watchface_wff is generated."

test-all:
    just check-core
