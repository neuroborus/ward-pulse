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
  command -v timeout >/dev/null || hold 'Required host executable not found: timeout'
  require_executable "$ANDROID"
  require_executable "$AVDMANAGER"
  require_executable "$EMULATOR"

  bounded 900 "$ANDROID" --sdk="$SDK_ROOT" sdk install \
    system-images/android-36/google_apis_playstore/x86_64

  local avds
  avds=$(bounded 10 "$EMULATOR" -list-avds) || hold 'Cannot list existing AVDs.'
  if ! grep -Fxq "$PHONE_AVD" <<< "$avds"; then
    printf 'no\n' | bounded 60 "$AVDMANAGER" create avd \
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

  if ! grep -Fxq "$WEAR_AVD" <<< "$avds"; then
    printf 'Required Wear AVD not found: %s\n' "$WEAR_AVD" >&2
    exit 1
  fi

  printf '%s\n' \
    "Start $PHONE_AVD and $WEAR_AVD in Android Studio." \
    "Pair them with Device Manager > Pair Wearable." \
    "Then run: just test-phone-watch-sync"
}

# All verification subprocesses, including server discovery, have a finite deadline.
# ADB's devices query is server-wide; -s has no filtering effect on that query.
bounded() {
  local seconds=$1
  shift
  timeout --kill-after=5s "${seconds}s" "$@"
}

hold() {
  printf 'HOLD: %s\n' "$*" >&2
  exit 1
}

adb_on() {
  local serial=$1
  shift
  bounded 5 "$ADB" -s "$serial" "$@"
}

resolve_devices() {
  local inventory serial state characteristics name features phone wear deadline=$((SECONDS + 30))
  local -a phones wears
  while (( SECONDS < deadline )); do
    # The selector is explicit even for the server-wide inventory operation.
    inventory=$(adb_on "${PHONE_SERIAL:-$PHONE_AVD}" devices) || hold 'ADB discovery failed.'
    phones=() wears=()
    while read -r serial state _; do
      [[ -z "$serial" || "$serial" == List || "$serial" == '*' ]] && continue
      (( SECONDS < deadline )) || hold 'Device discovery exceeded its deadline.'
      [[ "$serial" =~ ^[a-zA-Z0-9._:-]+$ ]] || hold 'Unrecognized ADB serial.'
      [[ "$state" == device ]] || hold 'An offline/unauthorized target is present; restore the existing pair first.'
      characteristics=$(adb_on "$serial" shell getprop ro.build.characteristics) || hold 'Cannot read live role.'
      characteristics=${characteristics//$'\r'/}
      [[ -n "$characteristics" ]] || hold 'Missing live device role.'
      if [[ ",$characteristics," == *,watch,* ]]; then wears+=("$serial"); else phones+=("$serial"); fi
    done <<< "$inventory"
    phone=${PHONE_SERIAL:-} wear=${WEAR_SERIAL:-}
    if [[ -z "$phone" ]]; then
      (( ${#phones[@]} <= 1 )) || hold 'Multiple phones are online; set PHONE_SERIAL explicitly.'
      (( ${#phones[@]} != 1 )) || phone=${phones[0]}
    fi
    if [[ -z "$wear" ]]; then
      (( ${#wears[@]} <= 1 )) || hold 'Multiple Wear devices are online; set WEAR_SERIAL explicitly.'
      (( ${#wears[@]} != 1 )) || wear=${wears[0]}
    fi
    if [[ -n "$phone" && -n "$wear" ]]; then
      [[ "$phone" != "$wear" && " ${phones[*]} " == *" $phone "* && " ${wears[*]} " == *" $wear "* ]] \
        || hold 'Serial override is offline, swapped or has the wrong role.'
      for serial in "$phone" "$wear"; do
        name=$(adb_on "$serial" emu avd name) || hold 'Cannot prove canonical AVD identity.'
        name=$(printf '%s\n' "$name" | tr -d '\r' | sed '/^OK$/d; /^$/d')
        features=$(adb_on "$serial" shell pm list features) || hold 'Cannot verify live device features.'
        features=${features//$'\r'/}
        if [[ "$serial" == "$phone" ]]; then
          [[ "$name" == "$PHONE_AVD" && $'\n'"$features"$'\n' == *$'\nfeature:android.hardware.telephony\n'* \
            && "$features" != *android.hardware.type.watch* ]] || hold 'Selected phone is not the live canonical phone.'
        else
          [[ "$name" == "$WEAR_AVD" && $'\n'"$features"$'\n' == *$'\nfeature:android.hardware.type.watch\n'* ]] \
            || hold 'Selected Wear target is not the live canonical watch.'
        fi
      done
      (( SECONDS < deadline )) || hold 'Device identity verification exceeded its deadline.'
      PHONE_SERIAL=$phone WEAR_SERIAL=$wear
      return
    fi
    sleep 1
  done
  hold 'Timed out discovering the online canonical phone and Wear pair.'
}

# ps is reconciled twice around /proc start-time reads. No cmdline, environment,
# private app data or arbitrary process output leaves the device.
processes() {
  adb_on "$1" shell '
    set -eu
    list() {
      raw=$(ps -A -o PID,NAME)
      printf "%s\n" "$raw" | awk '\''$2 == "app.wardpulse" || index($2, "app.wardpulse:") == 1 { print $1, $2 }'\'' | sort
    }
    identities() {
      before=$(list)
      if [ -n "$before" ]; then
        printf "%s\n" "$before" | while read -r pid name; do
          start=$(awk '\''{ sub(/^.*\) /, ""); print $20 }'\'' "/proc/$pid/stat")
          case "$start" in ""|*[!0-9]*) exit 1;; esac
          printf "%s %s %s\n" "$pid" "$start" "$name"
        done
      fi
      after=$(list)
      [ "$before" = "$after" ]
    }
    boot=$(cat /proc/sys/kernel/random/boot_id)
    first=$(identities)
    second=$(identities)
    [ "$first" = "$second" ]
    [ "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" ]
    printf "boot %s\n" "$boot"
    [ -z "$first" ] || printf "%s\n" "$first"
  ' | tr -d '\r'
}

app_processes() {
  local snapshot
  snapshot=$(processes "$1") || hold 'Process identity read failed or raced.'
  [[ "${snapshot%%$'\n'*}" == "boot ${BOOT[$2]}" ]] || hold 'Device rebooted during measurement.'
  printf '%s\n' "$snapshot" | sed '1d'
}

# Keep only safe event types and numeric PIDs. Raw log lines are never saved.
# The FIFO is a pipe, not a raw log file. Both owned readers are retired on exit.
start_monitor() {
  local role=$1 serial=$2
  mkfifo "$SCRATCH/$role.pipe"
  # Launch timeout directly so its recorded PID owns/forwards termination to ADB.
  timeout --kill-after=5s 1800s "$ADB" -s "$serial" logcat -b main -b events -v epoch -T 1 \
    WardPulseGate:I WardPulseSync:I am_proc_start:I am_proc_died:I chatty:I logd:W '*:S' \
    >"$SCRATCH/$role.pipe" 2>/dev/null &
  MONITORS+=("$!")
  awk '
    function emit(record) {
      bytes += length(record) + 1
      if (bytes > 262000) { print "GAP"; exit 1 }
      print record; fflush()
    }
    /^---------/ { next }
    {
      if ($1 !~ /^[0-9]+\.[0-9]+$/ || $1+0 < last_time) { emit("GAP"); next }
      last_time=$1+0
    }
    /chatty|logd|dropped|Unexpected EOF/ { emit("GAP"); next }
    /WardPulseGate/ {
      if (match($0, /wp-gate-[0-9]+-[0-9]+-[0-9]+/)) {
        gate_time=$1+0
        emit("MARK " substr($0, RSTART, RLENGTH))
      } else emit("GAP")
      next
    }
    /WardPulseSync/ {
      if ($0 ~ /^[0-9.]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseSync[ ]*: Watch summary received\.$/ && $1+0 > gate_time) emit("RECEIPT")
      else emit("GAP")
      next
    }
    /am_proc_start|am_proc_died/ {
      line=$0; sub(/^.*\[/, "", line); sub(/\].*$/, "", line)
      n=split(line, fields, ",")
      for (i=1; i<=n; i++) gsub(/^[ \t]+|[ \t]+$/, "", fields[i])
      name = /am_proc_start/ ? fields[4] : fields[3]
      if (name == "app.wardpulse" || index(name, "app.wardpulse:") == 1) {
        if (fields[2] !~ /^[0-9]+$/) emit("GAP")
        else emit((/am_proc_start/ ? "START " : "DEATH ") fields[2])
      } else if (index($0, "app.wardpulse")) emit("GAP")
    }
    END { print "GAP" }
  ' <"$SCRATCH/$role.pipe" >"$SCRATCH/$role.events" &
  MONITORS+=("$!")
}

barrier() {
  local role=$1 serial=$2 marker deadline pid line
  marker="wp-gate-$$-$((++SEQUENCE))-$SECONDS"
  adb_on "$serial" shell log -p i -t WardPulseGate "$marker" || hold 'Cannot place monitoring boundary.'
  deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    for pid in "${MONITORS[@]}"; do
      kill -0 "$pid" 2>/dev/null || hold 'Owned event monitor exited.'
    done
    [[ $(wc -c <"$SCRATCH/$role.events") -le 262144 ]] || hold 'Event observation exceeded its safe bound.'
    line=$(awk -v marker="$marker" '$0 == "MARK " marker { print NR }' "$SCRATCH/$role.events")
    if [[ -n "$line" ]]; then
      EVENTS=$(awk -v lo="${CURSOR[$role]:-0}" -v hi="$line" 'NR > lo && NR < hi && $1 != "MARK"' "$SCRATCH/$role.events")
      [[ "$EVENTS" != *GAP* ]] || hold 'Event loss or monitoring gap.'
      CURSOR[$role]=$line
      return
    fi
    sleep 0.1
  done
  hold 'Timed out reconciling the live event stream.'
}

summary_hash() {
  # The only consumer of watch_summary.xml is this hash-only pipeline.
  adb_on "$WEAR_SERIAL" exec-out \
    run-as "$APP_ID" cat shared_prefs/watch_summary.xml \
    | sha256sum \
    | cut -d' ' -f1
}

summary_metadata() {
  # Stat only: detect replacement/write evidence independently of content equality.
  adb_on "$WEAR_SERIAL" shell run-as "$APP_ID" \
    stat -c '%i:%s:%y:%z' shared_prefs/watch_summary.xml | tr -d '\r'
}

wait_for_stable_summary() {
  local current metadata previous= previous_metadata= deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    current=$(summary_hash) || hold 'Saved summary hash read failed.'
    metadata=$(summary_metadata) || hold 'Saved summary metadata read failed.'
    if [[ -n "$previous" && "$current" == "$previous" && "$metadata" == "$previous_metadata" ]]; then
      printf '%s\n' "$current"
      return
    fi
    previous=$current previous_metadata=$metadata
    sleep 1
  done
  hold 'Timed out waiting for a stable saved Wear summary.'
}

# Native JobScheduler records are NOT WorkManager logical specs. Project only
# the bounded, nonsecret subset before rejecting incomplete evidence. In
# particular, a WorkManager periodic request may be a native one-off job: its
# delay/network/native ID cannot establish cadence, UPDATE or REPLACE policy.
work_snapshot() {
  local metadata
  metadata=$(adb_on "$PHONE_SERIAL" shell '
    (dumpsys jobscheduler app.wardpulse && printf "\nWP_DONE\n") | awk '\''
    /^WP_DONE$/ { complete=1; next }
    /^[[:space:]]*JOB #[^:]+:.* app\.wardpulse\// {
      owned=1; jobs++
      if (jobs > 64 || $2 !~ /^#[a-zA-Z0-9_\/-]+:$/) exit 1
      print "native-job", substr($2, 1, length($2)-1); next
    }
    /^[[:space:]]*JOB #/ { owned=0 }
    owned && /Service: app\.wardpulse\/androidx\.work\.impl\.background\.systemjob\.SystemJobService/ { print "service WorkManager" }
    owned && /Required constraints:/ {
      print "network", (index($0, "CONNECTIVITY") ? "required" : "unknown")
    }
    END { if (!complete) exit 1; print "native-count", jobs+0 }
  '\''') || hold 'Cannot obtain bounded native scheduling metadata.'
  [[ $(printf '%s' "$metadata" | wc -c) -le 8192 ]] || hold 'Native scheduling metadata exceeds its safe bound.'
  printf '%s\n' "$metadata" >&2
  # No private WorkManager DB, diagnostics worker/broadcast, raw extras, account
  # data, or invented job may fill this gap. Do not disrupt preserved state.
  hold 'JobScheduler does not prove logical providerSync/recoveryWake correspondence, kind, cadence/reset delay and state. Work preservation is unobservable through the allowed interface; acceptance remains pending.'
}

require_no_receipts() {
  [[ "$1" != *RECEIPT* ]] || hold 'A new callback/publication invalidated retention, even if its bytes match.'
}

check_separation() {
  (( SECONDS < RETENTION_DEADLINE && SECONDS - LAST_OBSERVATION < 3 )) || hold 'Retention deadline or observation gap.'
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity/publication invalidated separation.'
  local current metadata phone
  phone=$(app_processes "$PHONE_SERIAL" phone) || hold 'Phone process observation failed.'
  [[ -z "$phone" ]] || hold 'Phone app is no longer absent.'
  current=$(summary_hash) || hold 'Retention summary hash read failed.'
  metadata=$(summary_metadata) || hold 'Retention summary stat failed.'
  [[ "$current" == "$BASELINE" && "$metadata" == "$BASELINE_METADATA" ]] || hold 'Saved summary changed or was replaced during retention.'
  (( SECONDS < RETENTION_DEADLINE && SECONDS - LAST_OBSERVATION < 3 )) || hold 'Retention observation was too slow to reconcile.'
  LAST_OBSERVATION=$SECONDS
}

stop_app() {
  local role=$1 serial=$2 required=$3 old current events= deadline identity expected actual
  barrier "$role" "$serial"
  if (( RETAINING )); then
    require_no_receipts "$EVENTS"
    [[ -z "$EVENTS" ]] || hold 'Unexpected app activity before intended death.'
  fi
  old=$(app_processes "$serial" "$role") || hold 'Cannot establish old process identities.'
  if [[ -z "$old" ]]; then
    printf '%s app was already absent; no death is claimed.\n' "$role"
    [[ "$required" == optional ]] || hold 'Retention requires an observed live Wear process before death.'
    return
  fi
  # Preserve all old PID/start identities, including :background processes.
  printf '%s old process identities:\n%s\n' "$role" "$old"
  adb_on "$serial" shell input keyevent KEYCODE_HOME || hold 'Cannot background the app.'
  adb_on "$serial" shell am kill "$APP_ID" || hold 'am kill failed.'
  deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if (( RETAINING )) && [[ "$role" == wear ]]; then check_separation; fi
    barrier "$role" "$serial"
    require_no_receipts "$EVENTS"
    events+="${EVENTS}"$'\n'
    [[ "$events" != *START* ]] || hold 'Replacement/background process started during intended death.'
    current=$(app_processes "$serial" "$role") || hold 'Process observation raced intended death.'
    while IFS= read -r identity; do
      [[ -z "$identity" ]] && continue
      [[ $'\n'"$old"$'\n' == *$'\n'"$identity"$'\n'* ]] || hold 'Unknown/reused process identity during intended death.'
    done <<< "$current"
    if [[ -z "$current" ]]; then
      expected=$(printf '%s\n' "$old" | awk '{ print "DEATH " $1 }' | sort)
      actual=$(printf '%s\n' "$events" | sed '/^$/d' | sort)
      [[ "$actual" == "$expected" ]] || hold 'Absence lacks reconciled death events for every old process.'
      sleep 0.2
      current=$(app_processes "$serial" "$role") || hold 'Cannot reconcile absence.'
      [[ -z "$current" ]] || hold 'Process reappeared after death.'
      barrier "$role" "$serial"
      [[ -z "$EVENTS" ]] || hold 'Activity raced the observed absence.'
      OLD[$role]=$old
      return
    fi
    sleep 0.2
  done
  hold 'Live old app process survived background/am kill; no restart is claimed.'
}

launch_app() {
  local role=$1 serial=$2 component=$3 current events= expected actual pid start deadline=$((SECONDS + 15))
  current=$(app_processes "$serial" "$role") || hold 'Cannot observe pre-launch absence.'
  [[ -z "$current" ]] || hold 'Launch target is already running; HOT is not restart.'
  adb_on "$serial" shell am start -W -n "$component" >/dev/null || hold 'Activity launch failed.'
  while (( SECONDS < deadline )); do
    if (( RETAINING )); then check_separation; fi
    barrier "$role" "$serial"
    if (( RETAINING )); then require_no_receipts "$EVENTS"; fi
    events+="${EVENTS}"$'\n'
    [[ "$events" != *DEATH* ]] || hold 'Launch process disappeared/reappeared.'
    current=$(app_processes "$serial" "$role") || hold 'Cannot establish launched process identity.'
    if [[ -n "$current" ]]; then
      expected=$(printf '%s\n' "$current" | awk '{ print "START " $1 }' | sort)
      actual=$(printf '%s\n' "$events" | sed '/^RECEIPT$/d; /^$/d' | sort)
      [[ "$actual" == "$expected" ]] || hold 'Launch lacks reconciled start events.'
      [[ $(printf '%s\n' "$current" | awk '$3 == "app.wardpulse" { n++ } END { print n+0 }') == 1 ]] || hold 'No unique new main app process.'
      while read -r pid start _; do
        if awk -v pid="$pid" -v start="$start" '$1 == pid && $2 == start { found=1 } END { exit !found }' <<< "${OLD[$role]:-}"; then
          hold 'Old process identity reused after launch.'
        fi
      done <<< "$current"
      RUNNING[$role]=$current
      # Receipts observed during launch still count toward fresh delivery.
      if [[ "$role" == wear && "$events" == *RECEIPT* ]]; then FRESH_RECEIPT=1; fi
      return
    fi
    sleep 0.2
  done
  hold 'Timed out proving a new app process after launch.'
}

wait_for_summary() {
  local current deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    barrier wear "$WEAR_SERIAL"
    [[ "$EVENTS" != *DEATH* && "$EVENTS" != *START* ]] || hold 'Wear process activity raced delivery.'
    [[ "$EVENTS" != *RECEIPT* ]] || FRESH_RECEIPT=1
    current=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot observe delivery process.'
    [[ "$current" == "${RUNNING[wear]}" ]] || hold 'Wear process changed during delivery.'
    if (( FRESH_RECEIPT )); then return; fi
    sleep 0.2
  done
  hold 'No fresh redacted WardPulseSync callback after the measurement boundary.'
}

package_update_time() {
  adb_on "$1" shell dumpsys package "$APP_ID" \
    | awk '/^[[:space:]]*lastUpdateTime=/ { sub(/^[[:space:]]*/, ""); print; n++ } END { if (n != 1) exit 1 }'
}

update_install() {
  local role=$1 serial=$2 apk=$3 before after result path installed built old current expected
  [[ -s "$apk" ]] || hold 'Current build did not produce the required debug APK.'
  built=$(sha256sum "$apk" | cut -d' ' -f1)
  before=$(package_update_time "$serial") || hold 'Cannot establish pre-update installed package identity.'
  barrier "$role" "$serial"
  old=$(app_processes "$serial" "$role") || hold 'Cannot record pre-update process identities.'
  printf '%s pre-update process identities (empty means already absent):\n%s\n' "$role" "$old"
  result=$(bounded 90 "$ADB" -s "$serial" install -r "$apk") || hold 'Data-preserving update install failed.'
  [[ "$result" == *Success* ]] || hold 'Package manager did not confirm the update.'
  after=$(package_update_time "$serial") || hold 'Cannot establish post-update installed package identity.'
  [[ "$before" != "$after" ]] || hold 'Installed package update time did not advance.'
  path=$(adb_on "$serial" shell pm path "$APP_ID") || hold 'Cannot resolve installed APK.'
  path=${path//$'\r'/} path=${path#package:}
  [[ "$path" =~ ^/data/app/[a-zA-Z0-9_./=+~-]+/base\.apk$ && "$path" != *'/../'* ]] || hold 'Unknown or split installed APK layout.'
  installed=$(adb_on "$serial" shell sha256sum "$path" | tr -d '\r' | cut -d' ' -f1) || hold 'Installed APK hash unavailable.'
  [[ "$installed" == "$built" ]] || hold 'Installed APK does not match this successful build.'
  current=$(app_processes "$serial" "$role") || hold 'Cannot observe post-update processes.'
  [[ -z "$current" ]] || hold 'Unexpected live app after update; update death cannot be reconciled.'
  barrier "$role" "$serial"
  expected=$(printf '%s\n' "$old" | awk 'NF { print "DEATH " $1 }' | sort)
  [[ $(printf '%s\n' "$EVENTS" | sed '/^$/d' | sort) == "$expected" ]] || hold 'Package update process deaths could not be reconciled.'
  work_snapshot
}

cleanup() {
  local pid
  for pid in "${MONITORS[@]}"; do kill "$pid" 2>/dev/null || :; done
  for pid in "${MONITORS[@]}"; do wait "$pid" 2>/dev/null || :; done
  [[ -z "$SCRATCH" ]] || rm -rf -- "$SCRATCH"
}

verify() {
  require_sdk_root
  require_executable "$ADB"
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || hold 'Flutter not found; set WARDPULSE_FLUTTER_BIN explicitly.'
  require_executable "$REPO_ROOT/apps/wear_android/gradlew"
  local tool role serial snapshot
  for tool in timeout awk sha256sum mktemp mkfifo sort sed tr cut wc; do
    command -v "$tool" >/dev/null || hold "Required host executable not found: $tool"
  done
  resolve_devices
  SCRATCH=$(mktemp -d)
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for role in phone wear; do
    if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
    snapshot=$(processes "$serial") || hold 'Cannot establish initial process identities.'
    BOOT[$role]=${snapshot%%$'\n'*}
    BOOT[$role]=${BOOT[$role]#boot }
    [[ "${BOOT[$role]}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || hold 'Missing boot identity.'
  done

  # Fail before any build/test/install/lifecycle disruption if preserved logical
  # work cannot be observed. This is an evidence gate, never a manual bypass.
  work_snapshot
  local phone_apk="$REPO_ROOT/apps/phone_flutter/build/app/outputs/flutter-apk/app-debug.apk"
  local wear_apk="$REPO_ROOT/apps/wear_android/app/build/outputs/apk/debug/app-debug.apk"
  rm -f -- "$phone_apk" "$wear_apk"
  (
    cd "$REPO_ROOT/apps/phone_flutter"
    bounded 900 "$FLUTTER_BIN" build apk --debug
  ) || hold 'Current Flutter debug build failed or timed out.'
  [[ -s "$phone_apk" ]] || hold 'Flutter did not recreate the debug APK.'
  start_monitor phone "$PHONE_SERIAL"
  start_monitor wear "$WEAR_SERIAL"
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot record pre-instrumentation identities.'
  printf 'Wear pre-instrumentation process identities (empty means absent):\n%s\n' "$snapshot"
  ANDROID_SERIAL="$WEAR_SERIAL" bounded 1200 "$REPO_ROOT/apps/wear_android/gradlew" \
    -p "$REPO_ROOT/apps/wear_android" --no-daemon --rerun-tasks connectedDebugAndroidTest \
    || hold 'Full Wear connectedDebugAndroidTest failed or timed out.'
  [[ -s "$wear_apk" ]] || hold 'Wear test build did not recreate the debug APK.'
  work_snapshot
  update_install phone "$PHONE_SERIAL" "$phone_apk"
  update_install wear "$WEAR_SERIAL" "$wear_apk"

  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  stop_app wear "$WEAR_SERIAL" optional
  stop_app phone "$PHONE_SERIAL" optional
  work_snapshot
  # A fresh stream barrier replaces logcat clearing; old receipts never count.
  barrier wear "$WEAR_SERIAL"
  FRESH_RECEIPT=0
  launch_app wear "$WEAR_SERIAL" "$APP_ID/app.wardpulse.wear.MainActivity"
  launch_app phone "$PHONE_SERIAL" "$APP_ID/.MainActivity"
  wait_for_summary
  BASELINE=$(wait_for_stable_summary)
  BASELINE_METADATA=$(summary_metadata) || hold 'Missing saved-summary metadata.'
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  RETAINING=1
  RETENTION_DEADLINE=$((SECONDS + 60)) LAST_OBSERVATION=$SECONDS
  stop_app phone "$PHONE_SERIAL" optional
  snapshot=$(app_processes "$PHONE_SERIAL" phone) || hold 'Cannot observe phone separation.'
  [[ -z "$snapshot" ]] || hold 'Phone did not separate.'
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity raced separation.'
  LAST_OBSERVATION=$SECONDS
  check_separation
  stop_app wear "$WEAR_SERIAL" required
  launch_app wear "$WEAR_SERIAL" "$APP_ID/app.wardpulse.wear.MainActivity"
  # SECONDS is integral: eleven ticks guarantee at least ten elapsed seconds.
  local until=$((SECONDS + 11)) after
  while (( SECONDS < until )); do
    check_separation
    barrier wear "$WEAR_SERIAL"
    [[ -z "$EVENTS" ]] || hold 'New Wear process/callback invalidated retention.'
    snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot observe retained Wear process.'
    [[ "$snapshot" == "${RUNNING[wear]}" ]] || hold 'Wear identity changed during retention.'
    sleep 0.2
  done
  after=$(wait_for_stable_summary)
  check_separation
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Late callback/process activity invalidated retention.'
  [[ "$BASELINE" == "$after" ]] || hold 'Saved Wear summary changed after actual restart.'
  work_snapshot
  check_separation
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Activity raced final preservation evidence.'
  snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Final Wear process observation failed.'
  [[ "$snapshot" == "${RUNNING[wear]}" ]] || hold 'Wear identity changed before completion.'
  printf '%s\n' 'Phone-to-watch acceptance passed.' \
    "Phone: $PHONE_AVD ($PHONE_SERIAL)" "Wear: $WEAR_AVD ($WEAR_SERIAL)" \
    "Saved summary SHA-256: $after"
}

declare -A BOOT=() OLD=() RUNNING=() CURSOR=()
MONITORS=()
SCRATCH= EVENTS= BASELINE= BASELINE_METADATA=
SEQUENCE=0 RETAINING=0 FRESH_RECEIPT=0 RETENTION_DEADLINE=0 LAST_OBSERVATION=0

case "${1:-}" in
  prepare) prepare ;;
  verify) verify ;;
  *)
    printf 'Usage: %s prepare|verify\n' "$0" >&2
    exit 2
    ;;
esac
