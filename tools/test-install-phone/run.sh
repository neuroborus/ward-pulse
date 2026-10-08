#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'install-phone regression failed: %s\n' "$*" >&2
  exit 1
}

fake_adb() {
  local scenario=${WARDPULSE_FAKE_ADB_SCENARIO:?}
  local state=${WARDPULSE_FAKE_ADB_STATE:?}
  local log=${WARDPULSE_FAKE_ADB_LOG:?}
  local expected_apk=${WARDPULSE_FAKE_ADB_APK:?}

  if [[ ${1:-} != -s || ${2:-} != test-phone ]]; then
    fail "unexpected adb target: $*"
  fi
  shift 2

  case ${1:-} in
    shell)
      [[ $# -eq 4 && $2 == dumpsys && $3 == package && $4 == app.wardpulse ]] ||
        fail "unexpected adb shell command: $*"
      printf 'dumpsys\n' >>"$log"
      if [[ $scenario == first-install && ! -f $state ]]; then
        return
      fi
      if [[ -f $state && ( $scenario == changed || $scenario == first-install ) ]]; then
        printf '  lastUpdateTime=2026-10-01 12:00:00\n'
      else
        printf '  lastUpdateTime=2026-09-11 10:00:00\n'
      fi
      ;;
    install)
      [[ $# -eq 3 && $2 == -r && $3 == "$expected_apk" ]] ||
        fail "unexpected adb install command: $*"
      printf 'install\n' >>"$log"
      if [[ $scenario == install-failure ]]; then
        printf 'adb: failed to install %s: Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]\n' \
          "$expected_apk" >&2
        return 1
      fi
      : >"$state"
      printf 'Success\n'
      ;;
    *)
      fail "unexpected adb command: $*"
      ;;
  esac
}

if [[ ${0##*/} == adb ]]; then
  fake_adb "$@"
  exit
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

mkdir "$TEMP_ROOT/bin"
ln -s "$SCRIPT_DIR/run.sh" "$TEMP_ROOT/bin/adb"

APK_PATH=apps/phone_flutter/build/app/outputs/flutter-apk/app-debug.apk

run_recipe() {
  local scenario=$1
  local state="$TEMP_ROOT/$scenario.state"
  local log="$TEMP_ROOT/$scenario.log"

  (
    cd "$REPO_ROOT"
    env \
      PATH="$TEMP_ROOT/bin:$PATH" \
      ANDROID_SERIAL=test-phone \
      WARDPULSE_FAKE_ADB_SCENARIO="$scenario" \
      WARDPULSE_FAKE_ADB_STATE="$state" \
      WARDPULSE_FAKE_ADB_LOG="$log" \
      WARDPULSE_FAKE_ADB_APK="$APK_PATH" \
      just install-phone
  )
}

missing_log="$TEMP_ROOT/missing-serial.log"
if output=$(
  cd "$REPO_ROOT"
  env \
    -u ANDROID_SERIAL \
    PATH="$TEMP_ROOT/bin:$PATH" \
    WARDPULSE_FAKE_ADB_SCENARIO=changed \
    WARDPULSE_FAKE_ADB_STATE="$TEMP_ROOT/missing-serial.state" \
    WARDPULSE_FAKE_ADB_LOG="$missing_log" \
    WARDPULSE_FAKE_ADB_APK="$APK_PATH" \
    just install-phone 2>&1
); then
  fail 'missing ANDROID_SERIAL was accepted'
fi
[[ $output == *'Set ANDROID_SERIAL to a phone device serial.'* ]] ||
  fail 'missing-serial error changed'
[[ ! -e $missing_log ]] || fail 'adb ran without ANDROID_SERIAL'

if output=$(run_recipe install-failure 2>&1); then
  fail 'adb install failure was ignored'
fi
[[ $output == *'INSTALL_FAILED_INSUFFICIENT_STORAGE'* ]] ||
  fail 'adb install failure output was lost'
[[ $(<"$TEMP_ROOT/install-failure.log") == $'dumpsys\ninstall' ]] ||
  fail 'the recipe continued after adb install failed'

if output=$(run_recipe unchanged 2>&1); then
  fail 'an unchanged lastUpdateTime was accepted'
fi
[[ $output == *'Phone package lastUpdateTime did not change after installation.'* ]] ||
  fail 'unchanged-timestamp error changed'

if ! output=$(run_recipe changed 2>&1); then
  printf '%s\n' "$output" >&2
  fail 'a changed lastUpdateTime was rejected'
fi

if ! output=$(run_recipe first-install 2>&1); then
  printf '%s\n' "$output" >&2
  fail 'a first installation was rejected'
fi

printf 'install-phone regression passed.\n'
