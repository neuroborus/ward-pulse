#!/usr/bin/env bash
set -euo pipefail

readonly CARGO_NDK_VERSION="4.1.2"
readonly NDK_VERSION="29.0.14206865"
readonly MIN_ANDROID_API="24"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

if [[ -z "${android_sdk}" ]]; then
  echo "Set ANDROID_HOME to the Android SDK directory." >&2
  exit 1
fi

ndk_home="${android_sdk}/ndk/${NDK_VERSION}"
if [[ ! -d "${ndk_home}" ]]; then
  echo "Missing Android NDK ${NDK_VERSION}: sdkmanager \"ndk;${NDK_VERSION}\"" >&2
  exit 1
fi

cargo_ndk_version="$(cargo ndk --version 2>/dev/null || true)"
if [[ "${cargo_ndk_version}" != "cargo-ndk ${CARGO_NDK_VERSION}" ]]; then
  echo "Install cargo-ndk ${CARGO_NDK_VERSION}: cargo install cargo-ndk --version ${CARGO_NDK_VERSION} --locked" >&2
  exit 1
fi

export ANDROID_NDK_HOME="${ndk_home}"

cd "${repo_root}/core"
cargo ndk \
  --target arm64-v8a \
  --target x86_64 \
  --platform "${MIN_ANDROID_API}" \
  --output-dir "${repo_root}/apps/phone_flutter/android/app/src/main/jniLibs" \
  build \
  --package ward-pulse-ffi \
  --release
