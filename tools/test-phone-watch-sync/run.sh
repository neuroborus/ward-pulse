#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
SDK_ROOT=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
PHONE_AVD=wardpulse_phone_play_api36
WEAR_AVD=wardpulse_wear_round_api36_1
APP_ID=app.wardpulse

ANDROID="$SDK_ROOT/cmdline-tools/latest/bin/android"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR="$SDK_ROOT/emulator/emulator"
FLUTTER_BIN=${WARDPULSE_FLUTTER_BIN:-$(command -v flutter || true)}

require_sdk_root() {
  if [[ -z "$SDK_ROOT" ]]; then
    printf 'Set ANDROID_HOME or ANDROID_SDK_ROOT to the Android SDK path.\n' >&2
    exit 1
  fi
  export ANDROID_HOME="$SDK_ROOT"
  export ANDROID_SDK_ROOT="$SDK_ROOT"
}

require_executable() {
  if [[ ! -x "$1" ]]; then
    printf 'Required executable not found: %s\n' "$1" >&2
    exit 1
  fi
}

prepare() {
  require_sdk_root
  require_executable "$ANDROID"
  require_executable "$AVDMANAGER"
  require_executable "$EMULATOR"

  "$ANDROID" --sdk="$SDK_ROOT" sdk install \
    system-images/android-36/google_apis_playstore/x86_64

  if ! "$EMULATOR" -list-avds | grep -Fxq "$PHONE_AVD"; then
    printf 'no\n' | "$AVDMANAGER" create avd \
      --name "$PHONE_AVD" \
      --package "system-images;android-36;google_apis_playstore;x86_64" \
      --device pixel_7
  fi

  local avd_root=${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-$HOME/.android}/avd}
  local config="$avd_root/$PHONE_AVD.avd/config.ini"
  if [[ ! -f "$config" ]]; then
    printf 'AVD configuration not found: %s\n' "$config" >&2
    exit 1
  fi
  sed -i 's/^PlayStore.enabled=no$/PlayStore.enabled=yes/' "$config"

  if ! "$EMULATOR" -list-avds | grep -Fxq "$WEAR_AVD"; then
    printf 'Required Wear AVD not found: %s\n' "$WEAR_AVD" >&2
    exit 1
  fi

  printf '%s\n' \
    "Start $PHONE_AVD and $WEAR_AVD in Android Studio." \
    "Pair them with Device Manager > Pair Wearable." \
    "Then run: just test-phone-watch-sync"
}

resolve_devices() {
  local _ serial characteristics selected_phone selected_wear
  local -a phones serials wears

  for _ in {1..10}; do
    phones=()
    wears=()
    mapfile -t serials < <(
      "$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }'
    )
    for serial in "${serials[@]}"; do
      characteristics=$("$ADB" -s "$serial" shell getprop ro.build.characteristics | tr -d '\r')
      if [[ ",${characteristics}," == *,watch,* ]]; then
        wears+=("$serial")
      else
        phones+=("$serial")
      fi
    done

    selected_phone=${PHONE_SERIAL:-}
    selected_wear=${WEAR_SERIAL:-}
    if [[ -z "$selected_phone" && ${#phones[@]} -eq 1 ]]; then
      selected_phone=${phones[0]}
    fi
    if [[ -z "$selected_wear" && ${#wears[@]} -eq 1 ]]; then
      selected_wear=${wears[0]}
    fi
    if [[ -n "$selected_phone" && -n "$selected_wear" ]]; then
      PHONE_SERIAL=$selected_phone
      WEAR_SERIAL=$selected_wear
      return
    fi
    if [[ -z ${PHONE_SERIAL:-} && ${#phones[@]} -gt 1 ]]; then
      printf 'Multiple phones are online; set PHONE_SERIAL explicitly.\n' >&2
      exit 1
    fi
    if [[ -z ${WEAR_SERIAL:-} && ${#wears[@]} -gt 1 ]]; then
      printf 'Multiple Wear devices are online; set WEAR_SERIAL explicitly.\n' >&2
      exit 1
    fi
    sleep 1
  done

  printf 'Expected one online phone and one online Wear device.\n' >&2
  exit 1
}

wait_for_summary() {
  local _
  for _ in {1..30}; do
    if "$ADB" -s "$WEAR_SERIAL" logcat -d -s WardPulseSync:I '*:S' \
      | grep -Fq 'Watch summary received.'; then
      return
    fi
    sleep 1
  done
  printf 'Timed out waiting for the Wear Data Layer summary.\n' >&2
  exit 1
}

summary_hash() {
  "$ADB" -s "$WEAR_SERIAL" exec-out \
    run-as "$APP_ID" cat shared_prefs/watch_summary.xml \
    | sha256sum \
    | cut -d' ' -f1
}

wait_for_stable_summary() {
  local _ current previous=
  for _ in {1..10}; do
    if ! current=$(summary_hash); then
      sleep 1
      continue
    fi
    if [[ -n "$previous" && "$current" == "$previous" ]]; then
      printf '%s\n' "$current"
      return
    fi
    previous=$current
    sleep 1
  done
  printf 'Timed out waiting for the saved Wear summary.\n' >&2
  exit 1
}

verify() {
  require_sdk_root
  require_executable "$ADB"
  if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
    printf 'Flutter not found; set WARDPULSE_FLUTTER_BIN explicitly.\n' >&2
    exit 1
  fi

  resolve_devices

  (
    cd "$REPO_ROOT/apps/phone_flutter"
    "$FLUTTER_BIN" build apk --debug
  )
  ANDROID_SERIAL="$WEAR_SERIAL" \
    "$REPO_ROOT/apps/wear_android/gradlew" \
    -p "$REPO_ROOT/apps/wear_android" \
    --no-daemon \
    connectedDebugAndroidTest

  "$ADB" -s "$PHONE_SERIAL" install -r \
    "$REPO_ROOT/apps/phone_flutter/build/app/outputs/flutter-apk/app-debug.apk"
  "$ADB" -s "$WEAR_SERIAL" install -r \
    "$REPO_ROOT/apps/wear_android/app/build/outputs/apk/debug/app-debug.apk"

  "$ADB" -s "$WEAR_SERIAL" logcat -c
  "$ADB" -s "$WEAR_SERIAL" shell am force-stop "$APP_ID"
  "$ADB" -s "$WEAR_SERIAL" shell am start \
    -n "$APP_ID/app.wardpulse.wear.MainActivity" >/dev/null
  "$ADB" -s "$PHONE_SERIAL" shell am force-stop "$APP_ID"
  "$ADB" -s "$PHONE_SERIAL" shell am start \
    -n "$APP_ID/.MainActivity" >/dev/null

  wait_for_summary

  local before after
  before=$(wait_for_stable_summary)
  "$ADB" -s "$PHONE_SERIAL" shell am force-stop "$APP_ID"
  "$ADB" -s "$WEAR_SERIAL" shell am force-stop "$APP_ID"
  "$ADB" -s "$WEAR_SERIAL" shell am start \
    -n "$APP_ID/app.wardpulse.wear.MainActivity" >/dev/null
  after=$(wait_for_stable_summary)
  if [[ "$before" != "$after" ]]; then
    printf 'The saved Wear summary changed after the Wear app restart.\n' >&2
    exit 1
  fi

  printf '%s\n' \
    "Phone-to-watch acceptance passed." \
    "Phone serial: $PHONE_SERIAL" \
    "Wear serial:  $WEAR_SERIAL"
}

case "${1:-}" in
  prepare) prepare ;;
  verify) verify ;;
  *)
    printf 'Usage: %s prepare|verify\n' "$0" >&2
    exit 2
    ;;
esac
