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
  bounded 5 "$ADB" -s "$serial" "$@" </dev/null
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
      characteristics=$(adb_on "$serial" shell -n getprop ro.build.characteristics) || hold 'Cannot read live role.'
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
        features=$(adb_on "$serial" shell -n pm list features) || hold 'Cannot verify live device features.'
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
  local uid=${UIDS[$2]}
  adb_on "$1" shell -n "uid=$uid" '
    set -eu
    list() {
      raw=$(ps -A -o UID,PID,NAME) || exit 1
      printf "%s\n" "$raw" | awk -v uid="$uid" '\''$1 == uid { print $2, $3 }'\'' | sort
    }
    identities() {
      before=$(list) || exit 1
      if [ -n "$before" ]; then
        printf "%s\n" "$before" | while read -r pid name; do
          start=$(awk '\''{ sub(/^.*\) /, ""); print $20 }'\'' "/proc/$pid/stat") || exit 1
          case "$start" in ""|*[!0-9]*) exit 1;; esac
          printf "%s %s %s\n" "$pid" "$start" "$name"
        done || return 1
      fi
      after=$(list) || exit 1
      [ "$before" = "$after" ]
    }
    boot=$(cat /proc/sys/kernel/random/boot_id) || exit 1
    first=$(identities) || exit 1
    second=$(identities) || exit 1
    [ "$first" = "$second" ]
    [ "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" ]
    printf "boot %s\n" "$boot"
    [ -z "$first" ] || printf "%s\n" "$first"
  ' | tr -d '\r'
}

app_processes() {
  local snapshot
  snapshot=$(processes "$1" "$2") || hold 'Process identity read failed or raced.'
  [[ "${snapshot%%$'\n'*}" == "boot ${BOOT[$2]}" ]] || hold 'Device rebooted during measurement.'
  local identities
  identities=$(printf '%s\n' "$snapshot" | sed '1d')
  # The observer is accounted for separately, only for its verified live identity.
  if [[ "$2" == phone && -n "$OBSERVER" ]]; then
    identities=$(printf '%s\n' "$identities" | awk -v observer="$OBSERVER" '$0 != observer')
  fi
  printf '%s' "$identities"
}

# Keep only safe event types and numeric PIDs. Raw log lines are never saved.
# The FIFO is a pipe, not a raw log file. Both owned readers are retired on exit.
start_monitor() {
  local role=$1 serial=$2 initial
  initial=$(app_processes "$serial" "$role" | awk '{ print $1 }')
  mkfifo "$SCRATCH/$role.pipe"
  # Launch timeout directly so its recorded PID owns/forwards termination to ADB.
  timeout --kill-after=5s 3600s "$ADB" -s "$serial" logcat -b main -b events -v epoch -T 1 \
    WardPulseGate:I WardPulseSync:I am_proc_start:I am_proc_died:I chatty:I logd:W '*:S' \
    >"$SCRATCH/$role.pipe" 2>/dev/null </dev/null &
  MONITORS+=("$!")
  awk -v role="$role" -v uid="${UIDS[$role]}" -v initial="$initial" '
    BEGIN { n=split(initial, pids, /[ \n]+/); for (i=1;i<=n;i++) owned[pids[i]]=1 }
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
      if (!owned[$2]) emit("GAP")
      else if (role == "phone" && $0 ~ /^[0-9.]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseSync[ ]*: Watch summary queued\.$/) emit("PUBLICATION")
      else if (role == "wear" && $0 ~ /^[0-9.]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseSync[ ]*: Watch summary received\.$/) emit("RECEIPT")
      else emit("GAP")
      next
    }
    /am_proc_start|am_proc_died/ {
      line=$0; sub(/^.*\[/, "", line); sub(/\].*$/, "", line)
      n=split(line, fields, ",")
      for (i=1; i<=n; i++) gsub(/^[ \t]+|[ \t]+$/, "", fields[i])
      name = /am_proc_start/ ? fields[4] : fields[3]
      is_start = /am_proc_start/
      if (n != (is_start ? 6 : 5) || fields[1] !~ /^[0-9]+$/ ||
          fields[2] !~ /^[0-9]+$/ || (is_start && fields[3] !~ /^[0-9]+$/) || !length(name)) {
        emit("GAP"); next
      }
      relevant = is_start ? fields[3] == uid : owned[fields[2]]
      if (relevant || name == "app.wardpulse" || index(name, "app.wardpulse:") == 1) {
        if (fields[2] !~ /^[0-9]+$/) emit("GAP")
        else {
          if (is_start) owned[fields[2]]=1
          else delete owned[fields[2]]
          emit((is_start ? "START " : "DEATH ") fields[2])
        }
      } else if (index($0, "app.wardpulse")) emit("GAP")
      next
    }
    { emit("GAP") }
    END { print "GAP" }
  ' <"$SCRATCH/$role.pipe" >"$SCRATCH/$role.events" &
  MONITORS+=("$!")
}

barrier() {
  local role=$1 serial=$2 marker deadline pid line
  marker="wp-gate-$$-$((++SEQUENCE))-$SECONDS"
  adb_on "$serial" shell -n log -p i -t WardPulseGate "$marker" || hold 'Cannot place monitoring boundary.'
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
      record_sync_events "$role"
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
  local metadata timestamp='[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{9} [+-][0-9]{4}'
  local pattern="^[1-9][0-9]*:[1-9][0-9]*:$timestamp:$timestamp$"
  metadata=$(adb_on "$WEAR_SERIAL" shell -n run-as "$APP_ID" \
    stat -c '%i:%s:%y:%z' shared_prefs/watch_summary.xml | tr -d '\r') || return 1
  [[ "$metadata" =~ $pattern && ${#metadata} -le 160 ]] || return 1
  printf '%s\n' "$metadata"
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

# Native correlation remains supplementary; WorkSpec determines periodicity.
native_jobs() {
  local label=$1 phone_live=$2 metadata
  metadata=$(adb_on "$PHONE_SERIAL" shell -n '
    (dumpsys jobscheduler app.wardpulse && printf "\nWP_DONE\n") | awk '\''
    function flush() {
      if (owned) print "native-job", id, wm+0, network+0
    }
    /^WP_DONE$/ { flush(); owned=0; complete=1; next }
    /^[[:space:]]*JOB #[^:]+:.* app\.wardpulse\// {
      flush()
      owned=1; jobs++
      if (jobs > 64 || $2 !~ /^#[a-zA-Z0-9_\/-]+:$/) exit 1
      id=$2; sub(/^.*\//, "", id); sub(/:$/, "", id)
      if (id !~ /^[0-9]+$/) exit 1
      wm=0; network=0; next
    }
    /^[[:space:]]*JOB #/ { flush(); owned=0 }
    owned && /Service: app\.wardpulse\/androidx\.work\.impl\.background\.systemjob\.SystemJobService/ { wm=1 }
    owned && /Required constraints:/ {
      network=(index($0, "CONNECTIVITY") ? 1 : 0)
    }
    END { if (!complete) exit 1; print "native-count", jobs+0 }
  '\''') || hold 'Cannot obtain bounded native scheduling metadata.'
  [[ $(printf '%s' "$metadata" | wc -c) -le 8192 ]] || hold 'Native scheduling metadata exceeds its safe bound.'
  printf '%s\n' "$metadata" >"$SCRATCH/native.current"
  awk -v previous_native="$SCRATCH/native.previous" -v previous_work="$SCRATCH/work.previous" \
    -v current_native="$SCRATCH/native.current" -v activity="$((PHONE_ACTIVITY - WORK_ACTIVITY))" \
    -v phone_live="$phone_live" -v stage="$label" '
    function fail() { bad=1; exit 1 }
    function same(x, y) { return ("x" x) == ("x" y) }
    function active(state) { return state == 0 || state == 1 || state == 4 }
    function rescheduled(a) {
      return activity && ($14 > a[14] || $19 > a[19] || $18 > a[18] ||
        !same($17, a[17]) || (a[4] == 1 && $4 == 0))
    }
    function explained_loss(a) {
      if (!activity) return 0
      if ($4 == 2) return 1
      if ($4 == 1 && phone_live && (a[4] == 0 || rescheduled(a))) return 1
      return $4 == 0 && rescheduled(a)
    }
    FILENAME == previous_native { if ($1 == "native-job") previous_job[$2]=1; next }
    FILENAME == previous_work { if ($1 == "WORK") old[$3]=$0; next }
    FILENAME == current_native {
      if ($1 == "native-job") {
        if (NF != 4 || $2 !~ /^[0-9]+$/ || ($2 in job) || $3 !~ /^[01]$/ || $4 !~ /^[01]$/) fail()
        job[$2]=$3; network[$2]=$4; jobs++
      } else if ($1 == "native-count") {
        if (NF != 2 || $2 !~ /^[0-9]+$/ || count++) fail()
        expected=$2
      } else fail()
      next
    }
    $1 == "WORK" {
      matched=$15 >= 0 && ($15 in job) && job[$15] == 1 && network[$15] == 1
      if (active($4) && $15 >= 0 && ($15 in job) && !matched) fail()
      if (active($4) && $15 >= 0) {
        if (($15 in owner) && owner[$15] != $3) fail()
        owner[$15]=$3
      }
      # An ENQUEUED spec claiming to be scheduled must have both its generation-
      # matched SystemIdInfo and the connected WorkManager job, even on preflight.
      if ($4 == 0 && $17 >= 0 && !matched) fail()
      prior=$3 in old
      if (prior) {
        split(old[$3], a, " ")
        mapping_changed=!same($14, a[14]) || !same($15, a[15])
        lost_job=(a[15] in previous_job) && !matched
        if (active(a[4]) && (mapping_changed || lost_job) && !explained_loss(a)) fail()
      }
      if (active($4) && !matched) {
        # A live RUNNING worker can consume its native job. A reset unscheduled
        # marker can explain a bounded rescheduling sample, never the final Pass.
        if ($4 == 1 && phone_live) next
        if ($4 == 0 && $17 == -1 && prior && stage != "final" && rescheduled(a)) next
        fail()
      }
    }
    END { if (bad || count != 1 || jobs+0 != expected) exit 1 }
  ' "$SCRATCH/native.previous" "$SCRATCH/work.previous" "$SCRATCH/native.current" \
    "$SCRATCH/work.current" || hold 'Native work correspondence was lost or changed without compatible execution/rescheduling evidence.'
  printf '%s\n' "$metadata" >&2
}

record_sync_events() {
  local role=$1 type pid extra key
  if (( LEDGER_READY )); then
    while read -r type pid extra; do
      [[ -n "$type" ]] || continue
      key="$role,${pid:-}"
      case "$type" in
        START)
          (( ! RETAINING )) || [[ "$LIFECYCLE_ACTION" == "$role:start" ]] \
            || hold 'Spontaneous/replacement process start invalidated retention.'
          [[ "$pid" =~ ^[0-9]+$ && -z "$extra" && ! -v "LIVE[$key]" ]] \
            || hold 'Duplicate/malformed app start; lifecycle continuity lost.'
          LIVE[$key]=1 ;;
        DEATH)
          (( ! RETAINING )) || [[ "$LIFECYCLE_ACTION" == "$role:death" ]] \
            || hold 'Unexpected process death invalidated retention.'
          [[ "$pid" =~ ^[0-9]+$ && -z "$extra" && -v "LIVE[$key]" ]] \
            || hold 'Unrecognized/malformed app death; lifecycle continuity lost.'
          unset 'LIVE[$key]' 'START_TICKS[$key]' ;;
        PUBLICATION|RECEIPT) [[ -z "$pid$extra" ]] || hold 'Malformed sync event.' ;;
        *) hold 'Unrecognized sanitized event.' ;;
      esac
    done <<< "$EVENTS"
  fi
  if [[ "$EVENTS" == *PUBLICATION* || "$EVENTS" == *RECEIPT* ]]; then
    (( ! RETAINING )) || hold 'Publication/callback invalidated quiet, including identical payloads.'
    if (( DELIVERING )); then
      [[ "$EVENTS" != *PUBLICATION* ]] || FRESH_PUBLICATION=1
      [[ "$EVENTS" != *RECEIPT* ]] || FRESH_RECEIPT=1
    fi
  fi
  if [[ "$1" == phone && -n "$EVENTS" ]]; then PHONE_ACTIVITY=$((PHONE_ACTIVITY + 1)); fi
}

reconcile_role() {
  local role=$1 serial=$2 current pid ticks name key expected= actual=
  barrier "$role" "$serial"
  current=$(app_processes "$serial" "$role") || hold 'Cannot reconcile observed processes.'
  barrier "$role" "$serial"
  for key in "${!LIVE[@]}"; do
    [[ "$key" != "$role,"* ]] || expected+="${key#*,}"$'\n'
  done
  while read -r pid ticks name; do
    [[ -n "$pid" ]] || continue
    key="$role,$pid"
    [[ ! -v "START_TICKS[$key]" || "${START_TICKS[$key]}" == "$ticks" ]] \
      || hold 'PID identity reuse lacks an observed death/start.'
    START_TICKS[$key]=$ticks
    actual+="$pid"$'\n'
  done <<< "$current"
  [[ $(printf '%s' "$actual" | sort) == "$(printf '%s' "$expected" | sort)" ]] \
    || hold 'Process inventory and lifecycle stream disagree.'
}

sender_coverage() {
  local apk=$1 manifest
  manifest=$(bounded 5 "$SDK_ROOT/build-tools/36.0.0/aapt2" dump xmltree \
    --file AndroidManifest.xml "$apk" 2>/dev/null) || hold 'Cannot inspect installed-equivalent merged components.'
  [[ ${#manifest} -le 131072 ]] || hold 'Merged manifest exceeds coverage bound.'
  printf '%s\n' "$manifest" | awk '
    /E: manifest / { manifest++ }
    /A: package="app.wardpulse"/ { package++ }
    /android:sharedUserId/ { bad=1 }
    /android:(isolatedProcess|externalService|useAppZygote)/ && !/\(type 0x12\)0x0$/ { bad=1 }
    /android:process/ {
      if ($0 !~ /="app\.wardpulse(:[a-zA-Z0-9_.]+)?"/) bad=1
    }
    /E: (activity|activity-alias|service|receiver|provider) / { components++ }
    END { if (bad || manifest != 1 || package != 1 || components < 5) exit 1 }
  ' || hold 'Installed sender components/processes are not fully covered by the UID/lifecycle monitor.'
  # Built APK == installed APK was checked by update_install. Source-owned UI,
  # refresh service and Workmanager BackgroundWorker all use the engine plugin;
  # no isolated/shared UID or uncovered manifest process is accepted here.
  [[ $(package_uid "$PHONE_SERIAL") == "${UIDS[phone]}" ]] || hold 'Installed sender UID changed.'
  SENDER_COVERED=1
}

package_uid() {
  local value
  value=$(adb_on "$1" shell -n cmd package list packages -U "$APP_ID" | tr -d '\r') \
    || hold 'Installed package UID unavailable.'
  [[ ${#value} -le 16384 ]] || hold 'Package UID inventory exceeds its bound.'
  # PackageManager applies a substring filter; watchface siblings are valid records.
  # Validate the entire bounded inventory, then require exactly the owned package.
  printf '%s\n' "$value" | awk -v package="$APP_ID" '
    function fail() { bad=1; exit 1 }
    {
      if (++rows > 128 || NF != 2 || $1 !~ /^package:[a-zA-Z0-9_.]+$/ ||
          !index($1, package) || $2 !~ /^uid:[0-9]+$/ || seen[$1]++) fail()
      uid=substr($2, 5)
      if (length(uid) > 10 || uid+0 < 1 || uid+0 > 2147483647) fail()
      if ($1 == "package:" package) { exact++; result=uid }
    }
    END { if (bad || exact != 1) exit 1; print result }
  ' || hold 'Package UID inventory is missing, malformed or ambiguous.'
}

installed_apk() {
  local path
  path=$(adb_on "$1" shell -n pm path "$APP_ID" | tr -d '\r') || hold 'Installed APK unavailable.'
  path=${path#package:}
  [[ "$path" =~ ^/data/app/[a-zA-Z0-9_./=+~-]+/base\.apk$ && "$path" != *'/../'* ]] \
    || hold 'Unknown or split installed APK layout.'
  printf '%s' "$path"
}

prepare_reader() {
  local version built staged
  JAVAC=$(command -v javac) || hold 'Existing javac 21 is required.'
  version=$(bounded 5 "$JAVAC" -version 2>&1) || hold 'Cannot identify javac.'
  [[ "$version" =~ ^javac\ 21[.] ]] || hold 'Existing javac 21 is required.'
  require_executable "$SDK_ROOT/build-tools/36.0.0/d8"
  require_executable "$SDK_ROOT/build-tools/36.0.0/aapt2"
  [[ -f "$SDK_ROOT/platforms/android-36/android.jar" ]] || hold 'Existing API36 android.jar is required.'
  mkdir "$SCRATCH/classes" "$SCRATCH/dex"
  bounded 30 "$JAVAC" --release 17 -cp "$SDK_ROOT/platforms/android-36/android.jar" \
    -d "$SCRATCH/classes" "$SCRIPT_DIR/WorkSnapshot.java" > /dev/null 2>&1 \
    || hold 'Bounded reader compilation failed.'
  bounded 30 "$SDK_ROOT/build-tools/36.0.0/d8" --min-api 36 \
    --lib "$SDK_ROOT/platforms/android-36/android.jar" --output "$SCRATCH/dex" \
    "$SCRATCH"/classes/WorkSnapshot*.class >/dev/null 2>&1 || hold 'Bounded reader DEX compilation failed.'
  [[ -s "$SCRATCH/dex/classes.dex" && $(wc -c <"$SCRATCH/dex/classes.dex") -le 65536 ]] \
    || hold 'Reader DEX exceeds its bound.'
  DEVICE_SCRATCH=$(adb_on "$PHONE_SERIAL" shell -n mktemp -d /data/local/tmp/wardpulse-sync.XXXXXXXX | tr -d '\r') \
    || hold 'Cannot allocate owned reader staging.'
  [[ "$DEVICE_SCRATCH" =~ ^/data/local/tmp/wardpulse-sync\.[a-zA-Z0-9]{8}$ ]] \
    || hold 'Unrecognized owned reader staging path.'
  adb_on "$PHONE_SERIAL" shell -n chmod 755 "$DEVICE_SCRATCH" || hold 'Cannot expose owned staging to app UID.'
  adb_on "$PHONE_SERIAL" push "$SCRATCH/dex/classes.dex" "$DEVICE_SCRATCH/reader.dex" >/dev/null \
    || hold 'Cannot stage owned reader DEX.'
  adb_on "$PHONE_SERIAL" shell -n chmod 444 "$DEVICE_SCRATCH/reader.dex" || hold 'Cannot make staged DEX read-only.'
  built=$(sha256sum "$SCRATCH/dex/classes.dex" | cut -d' ' -f1)
  staged=$(adb_on "$PHONE_SERIAL" shell -n sha256sum "$DEVICE_SCRATCH/reader.dex" | tr -d '\r' | cut -d' ' -f1) \
    || hold 'Cannot verify staged reader DEX.'
  [[ "$built" == "$staged" ]] || hold 'Staged reader differs from the current bounded build.'
}

work_snapshot() {
  local label=$1 apk pid ticks name header line output= end= reader_in reader_out reader_host
  local before_phone before_wear current phone_live=0 deadline=$((SECONDS + 8))
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  before_phone=$(app_processes "$PHONE_SERIAL" phone) || hold 'Pre-reader phone identity raced.'
  [[ -z "$before_phone" ]] || phone_live=1
  before_wear=$(app_processes "$WEAR_SERIAL" wear) || hold 'Pre-reader Wear identity raced.'
  apk=$(installed_apk "$PHONE_SERIAL")
  name="wardpulse-work-snapshot-$$"
  READER_STAGE_ACTIVE=1 READER_BEFORE_PHONE=$before_phone
  # This one ADB shell intentionally consumes GO from stdin, after identity verification.
  coproc WORK_READER { exec timeout --kill-after=1s 7s "$ADB" -s "$PHONE_SERIAL" shell -T \
    "run-as app.wardpulse env CLASSPATH=$DEVICE_SCRATCH/reader.dex app_process /system/bin --nice-name=$name WorkSnapshot ${UIDS[phone]} $apk" 2>/dev/null; }
  reader_host=${WORK_READER_PID:-}
  [[ "$reader_host" =~ ^[0-9]+$ ]] || hold 'Reader host process is unavailable.'
  READER_HOST=$reader_host
  exec {reader_out}<&"${WORK_READER[0]}" {reader_in}>&"${WORK_READER[1]}"
  IFS= read -r -t 2 header <&"$reader_out" || hold 'Reader DEX loading/UID/security handshake unavailable.'
  header=${header//$'\r'/}
  if [[ "$header" =~ ^HOLD\ [A-Z_]+$ ]]; then hold "Work reader: ${header#HOLD }"; fi
  [[ "$header" =~ ^READER\ ([0-9]+)\ ([0-9]+)$ ]] || hold 'Malformed reader handshake.'
  pid=${BASH_REMATCH[1]} ticks=${BASH_REMATCH[2]}
  OBSERVER="$pid $ticks $name"
  READER_DEVICE_PID=$pid
  current=$(processes "$PHONE_SERIAL" phone) || hold 'Cannot identify the actual reader process.'
  [[ $'\n'"$current"$'\n' == *$'\n'"$OBSERVER"$'\n'* ]] || hold 'Reader process identity is not observed.'
  printf 'Reader identity: %s\n' "$OBSERVER"
  printf 'GO\n' >&"$reader_in"
  exec {reader_in}>&-
  while IFS= read -r -t 2 line <&"$reader_out"; do
    line=${line//$'\r'/}
    (( SECONDS < deadline && ${#output} < 16384 )) || hold 'Reader exceeded output/time bounds.'
    if [[ "$line" == 'HOLD '* ]]; then
      [[ "$line" =~ ^HOLD\ [A-Z_]+$ ]] || hold 'Malformed reader failure.'
      hold "Work reader: ${line#HOLD }"
    fi
    if [[ "$line" == "END $pid $ticks" ]]; then end=1; break; fi
    [[ "$line" =~ ^(SCHEMA|SQLITE|TIME|WORK)\ [a-zA-Z0-9._:\ -]+$ ]] || hold 'Malformed or unrecognized reader output.'
    output+="$line"$'\n'
  done
  [[ "$end" == 1 ]] || hold 'Partial reader evidence.'
  if IFS= read -r -t 1 line <&"$reader_out"; then hold 'Unexpected trailing reader output.'; fi
  exec {reader_out}<&-
  wait "$reader_host" || hold 'Reader process failed or did not retire normally.'
  READER_HOST=
  adb_on "$PHONE_SERIAL" shell -n "test ! -e /proc/$pid" || hold 'Reader PID is still live or reused.'
  READER_DEVICE_PID= OBSERVER=
  READER_STAGE_ACTIVE=0
  current=$(app_processes "$PHONE_SERIAL" phone) || hold 'Post-reader phone identity raced.'
  [[ "$current" == "$before_phone" ]] || hold 'Reader interval included phone activity.'
  current=$(app_processes "$WEAR_SERIAL" wear) || hold 'Post-reader Wear identity raced.'
  [[ "$current" == "$before_wear" ]] || hold 'Reader interval included Wear activity.'
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'App start/death/publication raced work observation.'
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Wear activity raced work observation.'
  printf '%s' "$output" >"$SCRATCH/work.current"
  reconcile_work "$label"
  native_jobs "$label" "$phone_live"
  if [[ "$label" == preflight ]]; then
    # Keep the narrow installed tuple visible for HOST binding after scratch cleanup.
    awk '$1 == "SCHEMA" || $1 == "SQLITE"' "$SCRATCH/work.current"
  fi
  # Advance the accepted pair only after logical AND native evidence reconcile.
  cp "$SCRATCH/work.current" "$SCRATCH/work.previous"
  cp "$SCRATCH/native.current" "$SCRATCH/native.previous"
  WORK_ACTIVITY=$PHONE_ACTIVITY
  printf 'Bounded logical/native work reconciled: %s\n' "$label"
}

reconcile_work() {
  local label=$1
  # Validate the protocol independently of the Java reader, then reconcile only
  # documented transitions. Activity permits possible enqueue/execution, not
  # arbitrary spec changes or a claim about all intermediate transitions.
  awk -v previous="$SCRATCH/work.previous" -v activity="$((PHONE_ACTIVITY - WORK_ACTIVITY))" '
    function fail() { bad=1; exit 1 }
    function same(x, y) { return ("x" x) == ("x" y) }
    function terminal(state) { return state == 2 || state == 3 || state == 5 }
    function recovery_transition(before, after) {
      if (before == 0 || before == 1) return after == 0 || after == 1 || after == 2
      return before == 4 && (after == 4 || after == 0)
    }
    FILENAME == previous {
      if ($1 == "WORK") { old[$3]=$0; oldstate[$3]=$4; oldname[$3]=$2 }
      if ($1 == "TIME") oldtime=$2
      if ($1 == "SCHEMA") oldschema=$0
      if ($1 == "SQLITE") oldsqlite=$0
      next
    }
    $1 == "SCHEMA" {
      if (FNR != 1 || NF != 5 || $2 != "2.11.2" || $3 != 24 || $4 != "08b926448d86528e697981ddd30459f7" ||
          ($5 != "no_backup" && $5 != "databases") || schema++ || (oldschema && $0 != oldschema)) fail()
      next
    }
    $1 == "SQLITE" {
      source=$5; sub(/-alt[0-9]+$/, "", source)
      if (FNR != 2 || NF != 6 || ($2 != "3.44.3" && $2 != "3.44.4") ||
          $3 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ ||
          $4 !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ ||
          length(source) != 64 || source !~ /^[0-9a-f]+$/ || length($5) > 79 ||
          ($6 != "wal" && $6 != "delete") || sqlite++ || (oldsqlite && $0 != oldsqlite)) fail()
      next
    }
    $1 == "TIME" { if (FNR != 3 || NF != 2 || length($2) != 13 || $2 !~ /^[0-9]+$/ || time++) fail(); now=$2; next }
    $1 == "WORK" {
      if (schema != 1 || sqlite != 1 || time != 1 || NF != 25 || ++rows > 32 || seen[$3]++ ||
          ($2 != "wardpulse.providerSync" && $2 != "wardpulse.recoveryWake") ||
          $3 !~ /^[0-9a-f-]+$/ || $4 !~ /^[0-5]$/ ||
          $5 != "dev.fluttercommunity.workmanager.BackgroundWorker") fail()
      for (i=6;i<=25;i++) if ($i !~ /^-?[0-9]+$/) fail()
      if ($25 != -1 && $25 != 0 && $25 != 1) fail()
      if ($9 != 1 || $10 != 0 || $11 != 0 || $12 != 0 || $13 != 0) fail()
      if ($2 == "wardpulse.providerSync") {
        if ($6 < 900000 || $7 < 300000 || $7 > $6 || $4 == 4) fail()
        if ($4 == 0 || $4 == 1) {
          if (++periodic != 1 || (oldtime && !($3 in old))) fail()
        }
      } else if ($6 != 0 || $7 != 0 || $19 != 0) fail()
      if ($3 in old) {
        split(old[$3], a, " ")
        # Identity/spec preservation; initial delay is a spec, never a countdown.
        for (i=2;i<=14;i++) if (i != 4 && i != 14 && !same($i, a[i])) fail()
        if (!same($25, a[25])) fail()
        if (terminal(a[4])) {
          # Terminal identities cannot execute or be updated again. Only native
          # mapping/schedule retirement is compatible with terminal cleanup.
          for (i=2;i<=25;i++) {
            if ((i == 15 || i == 17) && $i == -1) continue
            if (!same($i, a[i])) fail()
          }
          if ($0 != old[$3] && !activity) fail()
          delete old[$3]
          next
        }
        if ($2 == "wardpulse.recoveryWake" &&
            (!same($14, a[14]) || !recovery_transition(a[4], $4))) fail()
        if ($14 < a[14] || $19 < a[19]) fail()
        if ($0 != old[$3]) {
          if (!activity) fail()
          # No unobserved cancellation/failure, override/backoff changes or reset rewrite.
          if ($4 == 3 || $4 == 5 || !same($20, a[20]) || !same($21, a[21]) ||
              !same($22, a[22]) || !same($23, a[23])) fail()
          if ($16 < a[16] || (!same($16, a[16]) && ($16 < oldtime || $16 > now))) fail()
          if ($18 < a[18] && $19 == a[19] && $4 != 0) fail()
        }
        delete old[$3]
      } else if (oldtime) {
        # REPLACE may create a new recovery identity while a real sender ran.
        if ($2 != "wardpulse.recoveryWake" || !activity || $4 != 0 ||
            $16 < oldtime || $16 > now || $14 != 0 || $19 != 0) fail()
        replacement=1
      }
      next
    }
    { fail() }
    END {
      if (bad || schema != 1 || sqlite != 1 || time != 1 || periodic != 1) exit 1
      for (id in old) {
        # Already-terminal history may be pruned for either logical name.
        if (oldstate[id] == 2 || oldstate[id] == 3 || oldstate[id] == 5) continue
        if (oldname[id] != "wardpulse.recoveryWake") exit 1
        # Active recovery loss needs replacement;
        # possible execution or a due timestamp alone does not prove its cause.
        if (!replacement) exit 1
      }
    }
  ' "$SCRATCH/work.previous" "$SCRATCH/work.current" || hold "Unexplained logical work transition at $label."
}

require_no_receipts() {
  [[ "$1" != *RECEIPT* && "$1" != *PUBLICATION* ]] || hold 'A new callback/publication invalidated retention, even if its bytes match.'
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
    [[ "$required" == optional ]] || hold 'Retention requires an observed live process before intended death.'
    return
  fi
  # Preserve all old PID/start identities, including :background processes.
  printf '%s old process identities:\n%s\n' "$role" "$old"
  adb_on "$serial" shell -n input keyevent KEYCODE_HOME || hold 'Cannot background the app.'
  LIFECYCLE_ACTION="$role:death"
  adb_on "$serial" shell -n am kill "$APP_ID" || hold 'am kill failed.'
  deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if (( RETAINING )) && [[ "$role" == wear ]]; then check_separation; fi
    barrier "$role" "$serial"
    if (( RETAINING )); then require_no_receipts "$EVENTS"; fi
    events+="${EVENTS}"$'\n'
    [[ "$events" != *START* ]] || hold 'Replacement/background process started during intended death.'
    current=$(app_processes "$serial" "$role") || hold 'Process observation raced intended death.'
    while IFS= read -r identity; do
      [[ -z "$identity" ]] && continue
      [[ $'\n'"$old"$'\n' == *$'\n'"$identity"$'\n'* ]] || hold 'Unknown/reused process identity during intended death.'
    done <<< "$current"
    if [[ -z "$current" ]]; then
      expected=$(printf '%s\n' "$old" | awk '{ print "DEATH " $1 }' | sort)
      actual=$(printf '%s\n' "$events" | awk '$1 == "START" || $1 == "DEATH"' | sort)
      [[ "$actual" == "$expected" ]] || hold 'Absence lacks reconciled death events for every old process.'
      sleep 0.2
      current=$(app_processes "$serial" "$role") || hold 'Cannot reconcile absence.'
      [[ -z "$current" ]] || hold 'Process reappeared after death.'
      barrier "$role" "$serial"
      [[ -z "$EVENTS" ]] || hold 'Activity raced the observed absence.'
      OLD[$role]=$old
      LIFECYCLE_ACTION=
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
  barrier "$role" "$serial"
  [[ -z "$EVENTS" ]] || hold 'Activity raced pre-launch absence.'
  LIFECYCLE_ACTION="$role:start"
  adb_on "$serial" shell -n am start -W -n "$component" >/dev/null || hold 'Activity launch failed.'
  while (( SECONDS < deadline )); do
    if (( RETAINING )); then check_separation; fi
    barrier "$role" "$serial"
    if (( RETAINING )); then require_no_receipts "$EVENTS"; fi
    events+="${EVENTS}"$'\n'
    [[ "$events" != *DEATH* ]] || hold 'Launch process disappeared/reappeared.'
    current=$(app_processes "$serial" "$role") || hold 'Cannot establish launched process identity.'
    if [[ -n "$current" ]]; then
      expected=$(printf '%s\n' "$current" | awk '{ print "START " $1 }' | sort)
      actual=$(printf '%s\n' "$events" | awk '$1 == "START" || $1 == "DEATH"' | sort)
      [[ "$actual" == "$expected" ]] || hold 'Launch lacks reconciled start events.'
      [[ $(printf '%s\n' "$current" | awk '$3 == "app.wardpulse" { n++ } END { print n+0 }') == 1 ]] || hold 'No unique new main app process.'
      if (( RETAINING )); then
        [[ $(printf '%s\n' "$current" | wc -l) == 1 ]] || hold 'Unexpected background Wear process during retention launch.'
      fi
      while read -r pid start _; do
        if awk -v pid="$pid" -v start="$start" '$1 == pid && $2 == start { found=1 } END { exit !found }' <<< "${OLD[$role]:-}"; then
          hold 'Old process identity reused after launch.'
        fi
      done <<< "$current"
      RUNNING[$role]=$current
      # Receipts observed during launch still count toward fresh delivery.
      if [[ "$role" == wear && "$events" == *RECEIPT* ]]; then FRESH_RECEIPT=1; fi
      LIFECYCLE_ACTION=
      return
    fi
    sleep 0.2
  done
  hold 'Timed out proving a new app process after launch.'
}

wait_for_summary() {
  local current deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    barrier phone "$PHONE_SERIAL"
    [[ "$EVENTS" != *DEATH* && "$EVENTS" != *START* ]] || hold 'Phone process activity raced delivery.'
    barrier wear "$WEAR_SERIAL"
    [[ "$EVENTS" != *DEATH* && "$EVENTS" != *START* ]] || hold 'Wear process activity raced delivery.'
    [[ "$EVENTS" != *RECEIPT* ]] || FRESH_RECEIPT=1
    current=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot observe delivery process.'
    [[ "$current" == "${RUNNING[wear]}" ]] || hold 'Wear process changed during delivery.'
    if (( FRESH_RECEIPT && FRESH_PUBLICATION )); then return; fi
    sleep 0.2
  done
  hold 'No fresh redacted WardPulseSync callback after the measurement boundary.'
}

package_update_time() {
  adb_on "$1" shell -n dumpsys package "$APP_ID" \
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
  # dumpsys timestamps have second precision; make a real same-APK update observable.
  sleep 1
  result=$(bounded 90 "$ADB" -s "$serial" install -r "$apk") || hold 'Data-preserving update install failed.'
  [[ "$result" == *Success* ]] || hold 'Package manager did not confirm the update.'
  after=$(package_update_time "$serial") || hold 'Cannot establish post-update installed package identity.'
  [[ "$after" > "$before" ]] || hold 'Installed package update time did not advance.'
  path=$(adb_on "$serial" shell -n pm path "$APP_ID") || hold 'Cannot resolve installed APK.'
  path=${path//$'\r'/} path=${path#package:}
  [[ "$path" =~ ^/data/app/[a-zA-Z0-9_./=+~-]+/base\.apk$ && "$path" != *'/../'* ]] || hold 'Unknown or split installed APK layout.'
  installed=$(adb_on "$serial" shell -n sha256sum "$path" | tr -d '\r' | cut -d' ' -f1) || hold 'Installed APK hash unavailable.'
  [[ "$installed" == "$built" ]] || hold 'Installed APK does not match this successful build.'
  if [[ "$role" == phone ]]; then
    PHONE_APK_PATH=$path PHONE_APK_HASH=$built PHONE_UPDATE_TIME=$after
  fi
  current=$(app_processes "$serial" "$role") || hold 'Cannot observe post-update processes.'
  [[ -z "$current" ]] || hold 'Unexpected live app after update; update death cannot be reconciled.'
  barrier "$role" "$serial"
  expected=$(printf '%s\n' "$old" | awk 'NF { print "DEATH " $1 }' | sort)
  [[ $(printf '%s\n' "$EVENTS" | awk '$1 == "START" || $1 == "DEATH"' | sort) == "$expected" ]] || hold 'Package update process deaths could not be reconciled.'
}

remove_reader_staging() {
  [[ -n "$DEVICE_SCRATCH" ]] || return 0
  [[ "$DEVICE_SCRATCH" =~ ^/data/local/tmp/wardpulse-sync\.[a-zA-Z0-9]{8}$ ]] || return 1
  adb_on "$PHONE_SERIAL" shell -n rm -f "$DEVICE_SCRATCH/reader.dex" || return 1
  adb_on "$PHONE_SERIAL" shell -n rmdir "$DEVICE_SCRATCH" || return 1
  DEVICE_SCRATCH=
}

verify_sender_identity() {
  local path hash updated
  (( SENDER_COVERED )) || hold 'Installed sender coverage is unproved.'
  path=$(installed_apk "$PHONE_SERIAL")
  updated=$(package_update_time "$PHONE_SERIAL") || hold 'Sender package update identity unavailable.'
  hash=$(adb_on "$PHONE_SERIAL" shell -n sha256sum "$path" | tr -d '\r' | cut -d' ' -f1) \
    || hold 'Sender package hash unavailable.'
  [[ "$path" == "$PHONE_APK_PATH" && "$hash" == "$PHONE_APK_HASH" && "$updated" == "$PHONE_UPDATE_TIME" \
    && $(package_uid "$PHONE_SERIAL") == "${UIDS[phone]}" ]] || hold 'Installed sender ownership changed.'
}

cleanup() {
  local result=$? pid deadline retired=1 current identity unknown
  trap - EXIT
  if [[ -n "$READER_HOST" ]]; then
    kill "$READER_HOST" 2>/dev/null || :
    wait "$READER_HOST" 2>/dev/null || :
  fi
  # The standalone reader also has its own six-second watchdog. Never kill an
  # application PID to hide a surviving observer, or call its lifetime absence.
  if [[ -n "$READER_DEVICE_PID" ]]; then
    deadline=$((SECONDS + 8))
    while ! adb_on "$PHONE_SERIAL" shell -n "test ! -e /proc/$READER_DEVICE_PID"; do
      if (( SECONDS >= deadline )); then
        printf 'HOLD: Reader retirement is unproved; owned staging retained.\n' >&2
        result=1 retired=0
        break
      fi
      sleep 0.2
    done
  fi
  if (( READER_STAGE_ACTIVE && retired )); then
    # Loading can fail before the handshake/watchdog. Reconcile the whole UID,
    # including native processes that ActivityManager would not log.
    deadline=$((SECONDS + 8))
    while :; do
      current=$(processes "$PHONE_SERIAL" phone) || { retired=0; result=1; break; }
      unknown=0
      while IFS= read -r identity; do
        [[ -n "$identity" ]] || continue
        [[ $'\n'"$READER_BEFORE_PHONE"$'\n' == *$'\n'"$identity"$'\n'* ]] || unknown=1
      done < <(printf '%s\n' "$current" | sed '1d')
      (( unknown )) || break
      if (( SECONDS >= deadline )); then retired=0; result=1; break; fi
      sleep 0.2
    done
    if (( ! retired )); then
      printf 'HOLD: Failed reader loading left unreconciled UID processes; staging retained.\n' >&2
    fi
  fi
  if (( retired )) && [[ -n "$DEVICE_SCRATCH" ]] && ! remove_reader_staging; then
    printf 'HOLD: Owned device reader staging could not be removed.\n' >&2
    result=1
  fi
  for pid in "${MONITORS[@]}"; do kill "$pid" 2>/dev/null || :; done
  for pid in "${MONITORS[@]}"; do wait "$pid" 2>/dev/null || :; done
  [[ -z "$SCRATCH" ]] || rm -rf -- "$SCRATCH"
  exit "$result"
}

verify() {
  require_sdk_root
  require_executable "$ADB"
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || hold 'Flutter not found; set WARDPULSE_FLUTTER_BIN explicitly.'
  require_executable "$REPO_ROOT/apps/wear_android/gradlew"
  local tool role serial snapshot pid ticks name key
  for tool in timeout awk sha256sum mktemp mkfifo sort sed tr cut wc cp grep mkdir rm rmdir sleep; do
    command -v "$tool" >/dev/null || hold "Required host executable not found: $tool"
  done
  (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) \
    || hold 'Bash 4.4 or newer is required.'
  resolve_devices
  SCRATCH=$(mktemp -d)
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  : >"$SCRATCH/work.previous"
  : >"$SCRATCH/native.previous"
  for role in phone wear; do
    if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
    UIDS[$role]=$(package_uid "$serial")
    snapshot=$(processes "$serial" "$role") || hold 'Cannot establish boot/process identities.'
    BOOT[$role]=${snapshot%%$'\n'*}
    BOOT[$role]=${BOOT[$role]#boot }
    [[ "${BOOT[$role]}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || hold 'Missing boot identity.'
  done
  start_monitor phone "$PHONE_SERIAL"
  start_monitor wear "$WEAR_SERIAL"
  # Bind the initial ledger only across an observed, stable bootstrap boundary.
  for role in phone wear; do
    if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
    barrier "$role" "$serial"
    snapshot=$(app_processes "$serial" "$role") || hold 'Cannot bind initial observed processes.'
    barrier "$role" "$serial"
    [[ -z "$EVENTS" ]] || hold 'Activity raced initial observation boundary.'
    while read -r pid ticks name; do
      [[ -n "$pid" ]] || continue
      key="$role,$pid"
      LIVE[$key]=1 START_TICKS[$key]=$ticks
    done <<< "$snapshot"
  done
  LEDGER_READY=1
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  prepare_reader
  work_snapshot preflight
  local phone_apk="$REPO_ROOT/apps/phone_flutter/build/app/outputs/flutter-apk/app-debug.apk"
  local wear_apk="$REPO_ROOT/apps/wear_android/app/build/outputs/apk/debug/app-debug.apk"
  rm -f -- "$phone_apk" "$wear_apk"
  (
    cd "$REPO_ROOT/apps/phone_flutter"
    bounded 900 "$FLUTTER_BIN" build apk --debug
  ) || hold 'Current Flutter debug build failed or timed out.'
  [[ -s "$phone_apk" ]] || hold 'Flutter did not recreate the debug APK.'
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  work_snapshot before-instrumentation
  snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot record pre-instrumentation identities.'
  printf 'Wear pre-instrumentation identities (empty means absent):\n%s\n' "$snapshot"
  ANDROID_SERIAL="$WEAR_SERIAL" bounded 1200 "$REPO_ROOT/apps/wear_android/gradlew" \
    -p "$REPO_ROOT/apps/wear_android" --no-daemon --rerun-tasks connectedDebugAndroidTest \
    || hold 'Full Wear connectedDebugAndroidTest failed or timed out.'
  [[ -s "$wear_apk" ]] || hold 'Wear test build did not recreate the debug APK.'
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  work_snapshot after-instrumentation
  update_install phone "$PHONE_SERIAL" "$phone_apk"
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  work_snapshot after-phone-update
  update_install wear "$WEAR_SERIAL" "$wear_apk"
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  work_snapshot after-wear-update
  sender_coverage "$phone_apk"

  stop_app wear "$WEAR_SERIAL" optional
  work_snapshot after-initial-wear-death
  stop_app phone "$PHONE_SERIAL" optional
  work_snapshot after-initial-phone-death
  # Both boundaries precede all delivery launches. Queued publication remains
  # distinct from the REQUIRED fresh Wear TYPE_CHANGED/save callback.
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  FRESH_RECEIPT=0 FRESH_PUBLICATION=0 DELIVERING=1
  launch_app wear "$WEAR_SERIAL" "$APP_ID/app.wardpulse.wear.MainActivity"
  work_snapshot after-delivery-wear-launch
  launch_app phone "$PHONE_SERIAL" "$APP_ID/.MainActivity"
  wait_for_summary
  DELIVERING=0
  reconcile_role phone "$PHONE_SERIAL"
  reconcile_role wear "$WEAR_SERIAL"
  work_snapshot after-delivery-phone-launch
  BASELINE=$(wait_for_stable_summary)
  BASELINE_METADATA=$(summary_metadata) || hold 'Missing saved-summary metadata.'
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  (( SENDER_COVERED )) || hold 'Installed sender ownership coverage is unproved.'
  RETAINING=1
  RETENTION_DEADLINE=$((SECONDS + 60)) LAST_OBSERVATION=$SECONDS
  stop_app phone "$PHONE_SERIAL" required
  snapshot=$(app_processes "$PHONE_SERIAL" phone) || hold 'Cannot observe phone separation.'
  [[ -z "$snapshot" ]] || hold 'Phone did not separate.'
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity raced separation.'
  LAST_OBSERVATION=$SECONDS
  check_separation
  work_snapshot after-retention-phone-death
  check_separation
  stop_app wear "$WEAR_SERIAL" required
  work_snapshot after-retention-wear-death
  check_separation
  launch_app wear "$WEAR_SERIAL" "$APP_ID/app.wardpulse.wear.MainActivity"
  work_snapshot after-retention-wear-launch
  check_separation
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
  work_snapshot final
  check_separation
  verify_sender_identity
  remove_reader_staging || hold 'Owned reader staging cleanup failed.'
  check_separation
  reconcile_role phone "$PHONE_SERIAL"
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity raced final preservation evidence.'
  reconcile_role wear "$WEAR_SERIAL"
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Wear activity raced final preservation evidence.'
  snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Final Wear process observation failed.'
  [[ "$snapshot" == "${RUNNING[wear]}" ]] || hold 'Wear identity changed before completion.'
  check_separation
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Wear activity raced completion.'
  printf '%s\n' 'Phone-to-watch acceptance passed.' \
    "Phone: $PHONE_AVD ($PHONE_SERIAL)" "Wear: $WEAR_AVD ($WEAR_SERIAL)" \
    "Saved summary SHA-256: $after"
}

declare -A BOOT=() OLD=() RUNNING=() CURSOR=() UIDS=() LIVE=() START_TICKS=()
MONITORS=()
SCRATCH= DEVICE_SCRATCH= EVENTS= BASELINE= BASELINE_METADATA= OBSERVER=
READER_HOST= READER_DEVICE_PID=
READER_STAGE_ACTIVE=0 READER_BEFORE_PHONE=
LIFECYCLE_ACTION=
PHONE_APK_PATH= PHONE_APK_HASH= PHONE_UPDATE_TIME=
SEQUENCE=0 RETAINING=0 DELIVERING=0 FRESH_RECEIPT=0 FRESH_PUBLICATION=0
RETENTION_DEADLINE=0 LAST_OBSERVATION=0 LEDGER_READY=0 SENDER_COVERED=0
PHONE_ACTIVITY=0 WORK_ACTIVITY=0

case "${1:-}" in
  prepare) prepare ;;
  verify) verify ;;
  *)
    printf 'Usage: %s prepare|verify\n' "$0" >&2
    exit 2
    ;;
esac
