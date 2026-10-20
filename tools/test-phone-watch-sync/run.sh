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
  if (( OBSERVING )); then
    local remaining=$((OBS_LIMIT - SECONDS))
    (( remaining > 0 )) || hold 'Observation deadline expired.'
    (( seconds <= remaining )) || seconds=$remaining
    timeout --kill-after=1s "${seconds}s" "$@"
    return
  fi
  timeout --kill-after=5s "${seconds}s" "$@"
}

hold() {
  if (( OBSERVING )); then
    OBS_ERROR=$*
    exit 1
  fi
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
  local -A seen
  while (( SECONDS < deadline )); do
    # The selector is explicit even for the server-wide inventory operation.
    inventory=$(adb_on "${PHONE_SERIAL:-$PHONE_AVD}" devices) || hold 'ADB discovery failed.'
    if (( OBSERVING )); then
      local printable=${inventory//$'\n'/}
      [[ ${#inventory} -le 32768 && "${printable//$'\t'/}" != *[[:cntrl:]]* ]] \
        || hold 'ADB discovery inventory exceeds observation bounds.'
    fi
    phones=() wears=() seen=()
    while read -r serial state _; do
      [[ -z "$serial" || "$serial" == List || "$serial" == '*' ]] && continue
      (( SECONDS < deadline )) || hold 'Device discovery exceeded its deadline.'
      [[ "$serial" =~ ^[a-zA-Z0-9._:-]+$ ]] || hold 'Unrecognized ADB serial.'
      if (( OBSERVING )); then
        [[ ! -v "seen[$serial]" ]] || hold 'Duplicate device identity in discovery.'
        seen[$serial]=1
      fi
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
  if (( OBSERVING )); then
    [[ ${#identities} -le 16384 ]] || hold 'Process inventory exceeds observation bounds.'
    printf '%s\n' "$identities" | awk '
      NF == 0 { next }
      { if (++rows > 128 || NF != 3 || $0 ~ /[[:cntrl:]]/ ||
          $1 !~ /^[0-9]+$/ || length($1) > 10 || $1+0 < 1 || $1+0 > 2147483647 || seen[$1]++ ||
          $2 !~ /^[0-9]+$/ || length($2) > 20 || $2+0 < 1 ||
          (length($2) == 20 && ("x" $2) > "x18446744073709551615") ||
          length($3) > 128 || $3 !~ /^app[.]wardpulse(:[a-zA-Z0-9_.]+)?$/) exit 1 }
    ' || hold 'App process identity is malformed, shared or ambiguous.'
    local pid ticks name
    while read -r pid ticks name; do
      [[ -n "$pid" ]] || continue
      observe_emit "PROCESS $OBS_REQUEST $OBS_PHASE $2 $pid $ticks $name" \
        || hold 'Cannot retain process identity.'
    done <<< "$identities"
  fi
  printf '%s' "$identities"
}

# Keep only safe event types and numeric PIDs. Raw log lines are never saved.
# The FIFO is a pipe, not a raw log file. Both owned readers are retired on exit.
start_monitor() {
  local role=$1 serial=$2 initial lifetime=3600 grace=5 closing=
  initial=$(app_processes "$serial" "$role" | awk '{ print $1 }')
  mkfifo "$SCRATCH/$role.pipe"
  : >"$SCRATCH/$role.events"
  if (( OBSERVING )); then
    lifetime=180 grace=1 closing="wp-gate-$$-0-${UIDS[$role]}"
    OBS_CLOSE[$role]=$closing
  fi
  # Launch timeout directly so its recorded PID owns/forwards termination to ADB.
  if (( OBSERVING )); then OBS_LAUNCHING=1; fi
  timeout --kill-after="${grace}s" "${lifetime}s" "$ADB" -s "$serial" logcat -b main -b events -v epoch -T 1 \
    WardPulseGate:I WardPulseSync:I am_proc_start:I am_proc_died:I am_kill:I chatty:I logd:W '*:S' \
    >"$SCRATCH/$role.pipe" 2>/dev/null </dev/null &
  MONITORS+=("$!")
  PRODUCERS[$role]=$!
  if (( OBSERVING )); then observe_launch_done; fi
  if (( OBSERVING )); then OBS_LAUNCHING=1; fi
  awk -v role="$role" -v uid="${UIDS[$role]}" -v initial="$initial" -v closing="$closing" '
    BEGIN {
      n=split(initial, pids, /[ \n]+/)
      for (i=1; i<=n; i++) if (length(pids[i])) owned[pids[i]]=""
    }
    function emit(record) {
      bytes += length(record) + 1
      if (bytes > 262000) { print "GAP"; exit 1 }
      print record; fflush()
    }
    /[[:cntrl:]]/ { emit("GAP"); next }
    /^---------/ { next }
    {
      if ($1 !~ /^[0-9]+\.[0-9]+$/ || $1+0 < last_time) { emit("GAP"); next }
      last_time=$1+0
    }
    /^[ ]*[0-9]+\.[0-9]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+am_(proc_start|proc_died|kill)[ ]*:/ {
      tag=$5; sub(/:.*/, "", tag)
      is_start=tag == "am_proc_start"; is_kill=tag == "am_kill"
      line=$0
      sub(/^[ ]*[0-9]+\.[0-9]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+am_(proc_start|proc_died|kill)[ ]*:[ ]*/, "", line)
      if (line !~ /^\[.*\][ ]*$/) {
        emit("GAP"); next
      }
      sub(/^\[/, "", line); sub(/\][ ]*$/, "", line)
      if (is_kill) {
        # Android 16: user, PID, name, adj, opaque String reason, long RSS.
        # Only the first four and last separators have structural meaning.
        for (i=1; i<=4; i++) {
          comma=index(line, ",")
          if (!comma) break
          fields[i]=substr(line, 1, comma-1); line=substr(line, comma+1)
        }
        if (i != 5 || !index(line, ",")) { emit("GAP"); next }
        rss=line; sub(/^.*,/, "", rss); gsub(/^[ ]+|[ ]+$/, "", rss)
        magnitude=rss; sub(/^-/, "", magnitude)
        limit=rss ~ /^-/ ? "9223372036854775808" : "9223372036854775807"
        if (rss !~ /^-?[0-9]+$/ || length(magnitude) > 19 ||
            (length(magnitude) == 19 && ("x" magnitude) > ("x" limit))) {
          emit("GAP"); next
        }
        n=4
      } else {
        if (line ~ /[][]/) { emit("GAP"); next }
        n=split(line, fields, ",")
      }
      for (i=1; i<=n; i++) gsub(/^[ \t]+|[ \t]+$/, "", fields[i])
      name=is_start ? fields[4] : fields[3]
      if (n != (is_start ? 6 : (is_kill ? 4 : 5)) ||
          fields[1] !~ /^[0-9]+$/ || length(fields[1]) > 10 || fields[1]+0 > 2147483647 ||
          fields[2] !~ /^[0-9]+$/ || length(fields[2]) > 10 || fields[2]+0 < 1 || fields[2]+0 > 2147483647 ||
          (is_start && (fields[3] !~ /^[0-9]+$/ || length(fields[3]) > 10 || fields[3]+0 < 1 || fields[3]+0 > 2147483647)) ||
          (!is_start && (fields[4] !~ /^-?[0-9]+$/ || length(fields[4]) > 11 || fields[4]+0 < -2147483648 || fields[4]+0 > 2147483647)) ||
          (!is_start && !is_kill && (fields[5] !~ /^-?[0-9]+$/ || length(fields[5]) > 11 || fields[5]+0 < -2147483648 || fields[5]+0 > 2147483647)) ||
          !length(name)) {
        emit("GAP"); next
      }
      relevant = is_start ? fields[3] == uid : (fields[2] in owned)
      if (relevant || name == "app.wardpulse" || index(name, "app.wardpulse:") == 1) {
        if ((length(closing) && name !~ /^app[.]wardpulse(:[a-zA-Z0-9_.]+)?$/) ||
            fields[1]+0 != int(uid/100000) ||
            (is_start && fields[3] != uid) ||
            (!is_start && (!(fields[2] in owned) ||
              (length(owned[fields[2]]) && owned[fields[2]] != name)))) emit("GAP")
        else {
          if (is_start || is_kill) owned[fields[2]]=name
          else delete owned[fields[2]]
          emit((is_start ? "START " : (is_kill ? "KILL " : "DEATH ")) fields[2])
        }
      } else if ((fields[2] in owned) || index(name, "app.wardpulse") ||
          (is_start && (index(fields[5], "app.wardpulse") || index(fields[6], "app.wardpulse")))) {
        separate = name == "app.wardpulse.test" && !(fields[2] in owned)
        if (is_start) {
          component=fields[6]
          gsub(/app[.]wardpulse[.]test([\/.}]|$)/, "", component)
          separate = separate && length(fields[5]) && length(fields[6]) &&
              !index(fields[5], "app.wardpulse") && !index(component, "app.wardpulse")
        }
        if (!separate) emit("GAP")
      }
      next
    }
    /chatty|logd|dropped|Unexpected EOF/ { emit("GAP"); next }
    /^[ ]*[0-9]+\.[0-9]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseGate[ ]*:/ {
      if (length(closing) && $0 !~ /: wp-gate-[0-9]+-[0-9]+-[0-9]+$/) {
        emit("GAP"); next
      }
      if (match($0, /wp-gate-[0-9]+-[0-9]+-[0-9]+/)) {
        gate_time=$1+0
        marker=substr($0, RSTART, RLENGTH)
        if (length(closing) && marker == closing) {
          closed=1; emit("CLOSE " marker); exit
        }
        emit("MARK " marker)
      } else emit("GAP")
      next
    }
    /WardPulseSync/ {
      if (!($2 in owned)) emit("GAP")
      else if (role == "phone" && $0 ~ /^[ ]*[0-9.]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseSync[ ]*: Watch summary queued\.$/) emit("PUBLICATION")
      else if (role == "wear" && $0 ~ /^[ ]*[0-9.]+[ ]+[0-9]+[ ]+[0-9]+[ ]+I[ ]+WardPulseSync[ ]*: Watch summary received\.$/) emit("RECEIPT")
      else emit("GAP")
      next
    }
    { emit("GAP") }
    END { if (!closed) print "GAP" }
  ' <"$SCRATCH/$role.pipe" >"$SCRATCH/$role.events" &
  MONITORS+=("$!")
  PROJECTORS[$role]=$!
  if (( OBSERVING )); then observe_launch_done; fi
}

barrier() {
  local role=$1 serial=$2 marker deadline pid line tag=MARK
  marker="wp-gate-$$-$((++SEQUENCE))-$SECONDS"
  if (( OBSERVING )) && [[ "${3:-}" == close ]]; then
    marker=${OBS_CLOSE[$role]} tag=CLOSE
  fi
  adb_on "$serial" shell -n log -p i -t WardPulseGate "$marker" || hold 'Cannot place monitoring boundary.'
  deadline=$((SECONDS + 5))
  if (( OBSERVING && deadline > OBS_LIMIT )); then deadline=$OBS_LIMIT; fi
  while (( SECONDS < deadline )); do
    [[ $(wc -c <"$SCRATCH/$role.events") -le 262144 ]] || hold 'Event observation exceeded its safe bound.'
    line=$(awk -v marker="$marker" -v tag="$tag" '$0 == tag " " marker { print NR }' "$SCRATCH/$role.events")
    [[ -z "$line" || "$line" =~ ^[1-9][0-9]*$ ]] || hold 'Monitoring boundary is ambiguous.'
    for pid in "${MONITORS[@]}"; do
      if (( OBSERVING )); then
        [[ "${OBS_CLOSED[$pid]:-0}" == 0 ]] || continue
        if [[ "$tag" == CLOSE && -n "$line" && ( "$pid" == "${PROJECTORS[$role]}" || "$pid" == "${PRODUCERS[$role]}" ) ]]; then
          continue
        fi
      fi
      kill -0 "$pid" 2>/dev/null || hold 'Owned event monitor exited.'
    done
    if [[ -n "$line" ]]; then
      EVENTS=$(awk -v lo="${CURSOR[$role]:-0}" -v hi="$line" 'NR > lo && NR < hi && $1 != "MARK" && $1 != "CLOSE"' "$SCRATCH/$role.events")
      if (( OBSERVING )); then
        observe_retain "$role" "$line" || hold 'Cannot retain typed observation results.'
      fi
      CURSOR[$role]=$line
      [[ "$EVENTS" != *GAP* ]] || hold 'Event loss or monitoring gap.'
      record_sync_events "$role"
      if [[ "$tag" == CLOSE ]]; then
        OBS_CLOSED[${PRODUCERS[$role]}]=1 OBS_CLOSED[${PROJECTORS[$role]}]=1
      fi
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
  local label=$1 phone_live=$2 metadata uid
  uid=$(package_uid "$PHONE_SERIAL")
  [[ "$uid" == "${UIDS[phone]}" ]] || hold 'Native scheduling package UID changed.'
  metadata=$(adb_on "$PHONE_SERIAL" shell -n '
    set -o pipefail || exit 1
    (dumpsys jobscheduler app.wardpulse 2>&1 && printf "\nWP_DONE\n") | awk -v uid='"$uid"' '\''
    function fail() { bad=1; exit 1 }
    function number(value, limit) {
      return value ~ /^(0|[1-9][0-9]*)$/ && length(value) <= 10 && value+0 <= limit
    }
    function counts(value, values, i) {
      if (split(value, values, "/") != 3) return 0
      for (i=1; i<=3; i++) if (values[i] != "-1" && !number(values[i], 2147483647)) return 0
      return 1
    }
    function hex_mask(value, i, result) {
      result=0
      for (i=4; i<length(value); i++) {
        result=result*16+index("0123456789abcdef", tolower(substr(value, i, 1)))-1
      }
      return result
    }
    function flush() {
      if (block && (services != 1 || constraints != 1)) fail()
      if (block && relevant) {
        if (!owned || !tagged || !wm || network != 1 ||
            seen_job[id]++ || ++jobs > 64) fail()
        inventory[jobs]="native-job " id " 1 1"
      }
      block=relevant=owned=tagged=services=wm=constraints=network=0
    }
    BEGIN {
      if (!number(uid, 2147483647) || uid%100000 < 10000 || uid%100000 >= 99000) fail()
      owner_uid=sprintf("u%da%d", int(uid/100000), uid%100000-10000)
      service="app.wardpulse/androidx.work.impl.background.systemjob.SystemJobService"
      work_namespace="androidx.work.systemjobscheduler"
      # JobStatus constraint bits; use unsigned arithmetic without awk extensions.
      constraint_bit["CHARGING"]=2^0
      constraint_bit["BATTERY_NOT_LOW"]=2^1
      constraint_bit["STORAGE_NOT_LOW"]=2^2
      constraint_bit["TARE_WEALTH"]=2^3
      constraint_bit["FLEXIBILITY"]=2^21
      constraint_bit["BACKGROUND_NOT_RESTRICTED"]=2^22
      constraint_bit["PREFETCH"]=2^23
      constraint_bit["WITHIN_QUOTA"]=2^24
      constraint_bit["DEVICE_NOT_DOZING"]=2^25
      constraint_bit["CONTENT_TRIGGER"]=2^26
      constraint_bit["IDLE"]=2^27
      constraint_bit["CONNECTIVITY"]=2^28
      constraint_bit["DEADLINE"]=2^30
      constraint_bit["TIMING_DELAY"]=2^31
    }
    {
      bytes+=length($0)+1
      if (complete || NR > 16384 || length($0) > 8192 || bytes > 1048576) fail()
      if (footer && NF && $0 != "WP_DONE") fail()
      lower=tolower($0)
      if (lower ~ /^[[:space:]]*(\*+|[a-z0-9_.$]*(exception|error)([[:space:]:]|$)|caused by:)/ ||
          lower ~ /^[[:space:]]*(failure|failed|timeout|truncated|aborted|fatal|warning|warn|unexpected|incomplete|partial)([[:space:]:]|$)/ ||
          lower ~ /^[[:space:]]*(permission denial|permission denied|can.t find service)([[:space:]:]|$)/ ||
          lower ~ /^[[:space:]]*at[[:space:]]+[a-z0-9_.$]+\(/ ||
          lower ~ /^[[:space:]]*(dump|dumpsys|binder|remote).*([[:space:]]|:)(failed|failure|error|exception|timeout|timed out|truncated)([[:space:]:]|$)/) fail()
    }
    /^WP_DONE$/ {
      if (block || !registered || !closed || !footer || blocks > registered_count) fail()
      complete=1; next
    }
    /^[[:space:]]*Registered/ {
      if (registered++ || NF != 3 || $1 != "Registered" || $3 != "jobs:" ||
          !number($2, 2147483647)) fail()
      registered_count=$2; registered_indent=match($0, /[^[:space:]]/)
      next
    }
    /^[[:space:]]*PersistStats/ {
      if (block || !registered || !closed || footer++ || NF != 5 ||
          $1 != "PersistStats:" || $2 != "FirstLoad:" || $4 != "LastSave:" ||
          !counts($3) || !counts($5) || match($0, /[^[:space:]]/) != registered_indent) fail()
      next
    }
    registered && !closed && /^[[:space:]]*JOB/ {
      flush()
      if (!registered || closed || $1 != "JOB" || NF != 4 || ++blocks > 256 || length($2) > 192 ||
          $3 !~ /^[0-9a-fA-F]+$/ || length($3) > 8 || $2 !~ /:$/) fail()
      identity=$2; sub(/:$/, "", identity)
      legacy=sub(/^#/, "", identity)
      parts=split(identity, namespaced, ":"); namespace=""
      if (parts == 2) {
        namespace=namespaced[1]; identity=namespaced[2]
        if (namespace !~ /^[a-zA-Z0-9_.-]+$/ || length(namespace) > 128) fail()
      } else if (parts != 1 || !legacy) fail()
      if (split(identity, pair, "/") != 2 || !number(pair[2], 2147483647)) fail()
      job_uid=pair[1]; id=pair[2]
      if (!number(job_uid, 2147483647)) {
        if (job_uid !~ /^u[0-9]+[ais][0-9]+$/ || length(job_uid) > 24) fail()
        user=job_uid; sub(/^u/, "", user); sub(/[ais].*$/, "", user)
        app=job_uid; sub(/^u[0-9]+[ais]/, "", app)
        if (!number(user, 21474) || !number(app, 99999)) fail()
      }
      if (seen_identity[namespace, job_uid, id]++) fail()
      tagged=index($4, "app.wardpulse/") > 0
      relevant=tagged || job_uid == owner_uid || ("x" job_uid) == ("x" uid)
      owned=(job_uid == owner_uid || ("x" job_uid) == ("x" uid)) &&
        (namespace == work_namespace || (legacy && namespace == ""))
      indent=match($0, /[^[:space:]]/)
      if (indent <= registered_indent) fail()
      block=1; next
    }
    {
      # A new section also ends a job; its records cannot complete the old block.
      if (block && NF && match($0, /[^[:space:]]/) <= indent) flush()
      if (registered && !closed && NF) {
        if (match($0, /[^[:space:]]/) <= registered_indent) {
          if ($0 !~ /^[[:space:]]*[a-zA-Z][a-zA-Z0-9_ ()-]*:$/) fail()
          closed=1
        } else if (!block) fail()
      }
      # Noninventory fields cannot complete or alter Registered job records.
      if (!registered || closed) next
    }
    $1 == "Service:" {
      if (!block) {
        if (index($0, "app.wardpulse/")) fail()
        next
      }
      if (NF != 2 || $2 !~ /^[a-zA-Z0-9_.]+\/[a-zA-Z0-9_.$]+$/ || services++) fail()
      wm=($2 == service)
      if (index($2, "app.wardpulse/") == 1) relevant=1
      next
    }
    $1 == "Required" && $2 == "constraints:" {
      if (!block || constraints++ || NF < 3 || $NF !~ /^\[0x[0-9a-fA-F]+\]$/ || length($NF) > 12) fail()
      expected_mask=0
      for (i=3; i<NF; i++) {
        if (!($i in constraint_bit) || seen_constraint[blocks, $i]++) fail()
        expected_mask+=constraint_bit[$i]
        if ($i == "CONNECTIVITY") network++
      }
      if (hex_mask($NF) != expected_mask) fail()
      next
    }
    /^[[:space:]]*(Service|Required[[:space:]]+constraints)/ {
      if (block || index($0, "app.wardpulse/")) fail()
    }
    END {
      if (bad || !complete || !jobs) exit 1
      for (i=1; i<=jobs; i++) print inventory[i]
      print "native-count", jobs
    }
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
  local role=$1 type pid extra key normalized=
  if (( LEDGER_READY )); then
    while read -r type pid extra; do
      [[ -n "$type" ]] || continue
      key="$role,${pid:-}"
      case "$type" in
        START)
          [[ "$LIFECYCLE_ACTION" != "$role:death" ]] \
            || hold 'Replacement/background process started during intended death.'
          (( ! RETAINING )) || [[ "$LIFECYCLE_ACTION" == "$role:start" ]] \
            || hold 'Spontaneous/replacement process start invalidated retention.'
          [[ "$pid" =~ ^[0-9]+$ && -z "$extra" && ! -v "LIVE[$key]" ]] \
            || hold 'Duplicate/malformed app start; lifecycle continuity lost.'
          [[ ! -v "KILLED[$key]" ]] || hold 'PID reuse after kill has an unresolved death notice.'
          if [[ "$LIFECYCLE_ACTION" == "$role:update" ]]; then
            [[ ! -v "START_TICKS[$key]" && ! -v "update_pids[$pid]" ]] \
              || hold 'PID reuse made update process ownership ambiguous.'
            # Include transient starts that never reach a sampled /proc identity.
            update_pids[$pid]=1
          fi
          LIVE[$key]=new ;;
        KILL)
          [[ "$LIFECYCLE_ACTION" != "$role:start" ]] || hold 'Launch process received a kill request.'
          (( ! RETAINING )) || [[ "$LIFECYCLE_ACTION" == "$role:death" ]] \
            || hold 'Unexpected process kill invalidated retention.'
          [[ "$pid" =~ ^[0-9]+$ && -z "$extra" && -v "LIVE[$key]" && ! -v "KILLED[$key]" ]] \
            || hold 'Unrecognized/duplicate app kill; lifecycle continuity lost.'
          # Intent alone leaves both the live identity and publication ownership intact.
          KILLED[$key]=pending ;;
        DEATH)
          [[ "$pid" =~ ^[0-9]+$ && -z "$extra" ]] || hold 'Malformed app death.'
          if [[ "${KILLED[$key]:-}" == absent && ! -v "LIVE[$key]" ]]; then
            # One late corroboration of the same removal, with no intervening START.
            unset 'KILLED[$key]'
            continue
          fi
          [[ "$LIFECYCLE_ACTION" != "$role:start" ]] || hold 'Launch process disappeared/reappeared.'
          (( ! RETAINING )) || [[ "$LIFECYCLE_ACTION" == "$role:death" ]] \
            || hold 'Unexpected process death invalidated retention.'
          [[ -v "LIVE[$key]" ]] \
            || hold 'Unrecognized/malformed app death; lifecycle continuity lost.'
          # Keep sampled ticks to reject reuse of that identity by a later START.
          unset 'LIVE[$key]'
          if [[ "${KILLED[$key]:-}" == pending ]]; then
            unset 'KILLED[$key]'
            continue
          fi ;;
        PUBLICATION|RECEIPT) [[ -z "$pid$extra" ]] || hold 'Malformed sync event.' ;;
        *) hold 'Unrecognized sanitized event.' ;;
      esac
      normalized+="$type${pid:+ $pid}"$'\n'
    done <<< "$EVENTS"
    EVENTS=${normalized%$'\n'}
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
  [[ "$EVENTS" != *START* && "$EVENTS" != *KILL* && "$EVENTS" != *DEATH* ]] \
    || hold 'Process lifecycle changed across the inventory boundary.'
  [[ $# -lt 3 || "$current" == "${3-}" ]] || hold 'Process identities changed across the lifecycle action boundary.'
  while read -r pid ticks name; do
    [[ -n "$pid" ]] || continue
    key="$role,$pid"
    [[ -v "LIVE[$key]" ]] || hold 'Observed process lacks lifecycle ownership.'
    if [[ -v "START_TICKS[$key]" ]]; then
      if [[ "${LIVE[$key]}" == new ]]; then
        [[ "${START_TICKS[$key]}" != "$ticks" ]] || hold 'New start reused an old process identity.'
      else
        [[ "${START_TICKS[$key]}" == "$ticks" ]] || hold 'PID identity reuse lacks an observed death/start.'
      fi
    fi
    LIVE[$key]=1
    START_TICKS[$key]=$ticks
    actual+="$pid"$'\n'
  done <<< "$current"
  for key in "${!LIVE[@]}"; do
    [[ "$key" == "$role,"* ]] || continue
    if [[ $'\n'"$actual" != *$'\n'"${key#*,}"$'\n'* && "${KILLED[$key]:-}" == pending ]]; then
      # The validated START may have lived wholly between inventories. No
      # retrospective /proc read or invented start tick is evidence for it.
      unset 'LIVE[$key]'
      KILLED[$key]=absent
    else
      expected+="${key#*,}"$'\n'
    fi
  done
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
  local role=$1 serial=$2 required=$3 old current events= identity key pending
  local deadline=$((SECONDS + 15))
  # The foreground STOP owns one budget, including its surrounding boundaries.
  if (( OBSERVING && deadline > OBS_LIMIT )); then deadline=$OBS_LIMIT; fi
  barrier "$role" "$serial"
  (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
  if (( RETAINING )); then
    require_no_receipts "$EVENTS"
    [[ -z "$EVENTS" ]] || hold 'Unexpected app activity before intended death.'
  fi
  old=$(app_processes "$serial" "$role") || hold 'Cannot establish old process identities.'
  (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
  reconcile_role "$role" "$serial" "$old"
  (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
  if [[ -z "$old" ]]; then
    printf '%s app was already absent; no death is claimed.\n' "$role"
    [[ "$required" == optional ]] || hold 'Retention requires an observed live process before intended death.'
    return
  fi
  # Preserve all old PID/start identities, including :background processes.
  printf '%s old process identities:\n%s\n' "$role" "$old"
  LIFECYCLE_ACTION="$role:death"
  adb_on "$serial" shell -n input keyevent KEYCODE_HOME || hold 'Cannot background the app.'
  (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
  while (( SECONDS < deadline )); do
    if (( RETAINING )) && [[ "$role" == wear ]]; then check_separation; fi
    (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
    barrier "$role" "$serial"
    (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
    if (( RETAINING )); then require_no_receipts "$EVENTS"; fi
    events+="${EVENTS}"$'\n'
    [[ "$events" != *START* ]] || hold 'Replacement/background process started during intended death.'
    current=$(app_processes "$serial" "$role") || hold 'Process observation raced intended death.'
    (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
    while IFS= read -r identity; do
      [[ -z "$identity" ]] && continue
      [[ $'\n'"$old"$'\n' == *$'\n'"$identity"$'\n'* ]] || hold 'Unknown/reused process identity during intended death.'
    done <<< "$current"
    if [[ -z "$current" ]]; then
      sleep 0.2
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
      current=$(app_processes "$serial" "$role") || hold 'Cannot reconcile absence.'
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
      [[ -z "$current" ]] || hold 'Process reappeared after death.'
      barrier "$role" "$serial"
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
      [[ -z "$EVENTS" ]] || hold 'Activity raced the observed absence.'
      reconcile_role "$role" "$serial" ""
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
      OLD[$role]=$old
      LIFECYCLE_ACTION=
      return
    fi
    reconcile_role "$role" "$serial" "$current"
    (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
    # KILL retains live identity and publication ownership until the existing
    # ledger reconciles death or stable absence; do not reissue while pending.
    pending=0
    for key in "${!KILLED[@]}"; do
      if [[ "$key" == "$role,"* && "${KILLED[$key]}" == pending ]]; then pending=1; fi
    done
    if (( ! pending )); then
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
      adb_on "$serial" shell -n am kill "$APP_ID" || hold 'am kill failed.'
      (( SECONDS < deadline )) || hold 'Intended death exceeded its deadline.'
    fi
    sleep 0.2
  done
  hold 'Live old app process survived background/am kill; no restart is claimed.'
}

launch_app() {
  local role=$1 serial=$2 component=$3 current events= expected actual pid start deadline=$((SECONDS + 15))
  local OBS_LIMIT=$OBS_LIMIT launch launch_diagnostic
  if (( OBSERVING && deadline < OBS_LIMIT )); then OBS_LIMIT=$deadline; fi
  current=$(app_processes "$serial" "$role") || hold 'Cannot observe pre-launch absence.'
  [[ -z "$current" ]] || hold 'Launch target is already running; HOT is not restart.'
  barrier "$role" "$serial"
  [[ -z "$EVENTS" ]] || hold 'Activity raced pre-launch absence.'
  LIFECYCLE_ACTION="$role:start"
  if (( OBSERVING )); then
    launch=$(adb_on "$serial" shell -n am start -W -n "$component" | tr -d '\r') || hold 'Activity launch failed.'
    [[ ${#launch} -le 16384 && "${launch//$'\n'/}" != *[[:cntrl:]]* ]] || hold 'Malformed activity launch result.'
    launch_diagnostic=$(printf '%s\n' "$launch" | awk '
      /^Status:/ { status++; if ($0 != "Status: ok") bad=1; else status_ok=1 }
      /^LaunchState:/ {
        state++; if ($0 != "LaunchState: COLD") bad=1
        if ($0 == "LaunchState: COLD") launch_state="COLD"
        else if ($0 == "LaunchState: WARM") launch_state="WARM"
        else if ($0 == "LaunchState: HOT") launch_state="HOT"
        else if ($0 == "LaunchState: RELAUNCH") launch_state="RELAUNCH"
        else if ($0 == "LaunchState: UNKNOWN (0)") launch_state="UNKNOWN"
        else launch_state="OTHER"
      }
      /Warning:/ {
        warning_count++
        if ($0 == "Warning: Activity not started because the  current activity is being kept for the user.") switches_canceled=1
        else if ($0 == "Warning: Activity not started, intent has been delivered to currently running top-most instance.") intent_delivered_to_top=1
        else if ($0 == "Warning: Activity not started because intent should be handled by the caller") return_intent_to_caller=1
        else if ($0 == "Warning: Activity not started, its current task has been brought to the front") task_to_front=1
        else other_warning=1
      }
      /Error:/ { error=1 }
      /Exception/ { exception=1 }
      /Error:|Exception/ { bad=1 }
      END {
        if (bad || status != 1 || state != 1 || warning_count > task_to_front) {
          printf "StatusCount=%s Status=%s LaunchStateCount=%s LaunchState=%s", \
            (status == 0 ? "MISSING" : status == 1 ? "ONE" : "MULTIPLE"), \
            (status == 1 && status_ok ? "OK" : "NON_OK"), \
            (state == 0 ? "MISSING" : state == 1 ? "ONE" : "MULTIPLE"), \
            (state == 1 ? launch_state : "OTHER")
          printf " SWITCHES_CANCELED=%d INTENT_DELIVERED_TO_TOP=%d RETURN_INTENT_TO_CALLER=%d", \
            switches_canceled+0, intent_delivered_to_top+0, return_intent_to_caller+0
          printf " TASK_TO_FRONT=%d OTHER_WARNING=%d ERROR=%d EXCEPTION=%d\n", \
            task_to_front+0, other_warning+0, error+0, exception+0
          exit 1
        }
      }
    ') || hold "Launch did not prove a successful COLD load; HOT is not restart. ${launch_diagnostic:-DIAGNOSTIC_UNAVAILABLE}"
  else
    adb_on "$serial" shell -n am start -W -n "$component" >/dev/null || hold 'Activity launch failed.'
  fi
  while (( SECONDS < deadline )); do
    if (( RETAINING )); then check_separation; fi
    barrier "$role" "$serial"
    if (( RETAINING )); then require_no_receipts "$EVENTS"; fi
    events+="${EVENTS}"$'\n'
    [[ "$events" != *KILL* && "$events" != *DEATH* ]] || hold 'Launch process disappeared/reappeared.'
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
      if (( OBSERVING )); then
        (( SECONDS < OBS_LIMIT )) || hold 'Launch exceeded its deadline.'
      fi
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
    [[ "$EVENTS" != *KILL* && "$EVENTS" != *DEATH* && "$EVENTS" != *START* ]] || hold 'Phone process activity raced delivery.'
    barrier wear "$WEAR_SERIAL"
    [[ "$EVENTS" != *KILL* && "$EVENTS" != *DEATH* && "$EVENTS" != *START* ]] || hold 'Wear process activity raced delivery.'
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
  local role=$1 serial=$2 apk=$3 before after result path installed built old current pid ticks name key
  local -A update_pids=()
  [[ -s "$apk" ]] || hold 'Current build did not produce the required debug APK.'
  built=$(sha256sum "$apk" | cut -d' ' -f1)
  [[ $(package_uid "$serial") == "${UIDS[$role]}" ]] || hold 'Pre-update package UID changed.'
  before=$(package_update_time "$serial") || hold 'Cannot establish pre-update installed package identity.'
  # dumpsys timestamps have second precision; make a real same-APK update observable.
  sleep 1
  barrier "$role" "$serial"
  old=$(app_processes "$serial" "$role") || hold 'Cannot record pre-update process identities.'
  reconcile_role "$role" "$serial" "$old"
  printf '%s pre-update process identities (empty means already absent):\n%s\n' "$role" "$old"
  LIFECYCLE_ACTION="$role:update"
  result=$(bounded 90 "$ADB" -s "$serial" install -r "$apk") || hold 'Data-preserving update install failed.'
  [[ "$result" == *Success* ]] || hold 'Package manager did not confirm the update.'
  after=$(package_update_time "$serial") || hold 'Cannot establish post-update installed package identity.'
  [[ "$after" > "$before" ]] || hold 'Installed package update time did not advance.'
  path=$(adb_on "$serial" shell -n pm path "$APP_ID") || hold 'Cannot resolve installed APK.'
  path=${path//$'\r'/} path=${path#package:}
  [[ "$path" =~ ^/data/app/[a-zA-Z0-9_./=+~-]+/base\.apk$ && "$path" != *'/../'* ]] || hold 'Unknown or split installed APK layout.'
  installed=$(adb_on "$serial" shell -n sha256sum "$path" | tr -d '\r' | cut -d' ' -f1) || hold 'Installed APK hash unavailable.'
  [[ "$installed" == "$built" ]] || hold 'Installed APK does not match this successful build.'
  [[ $(package_uid "$serial") == "${UIDS[$role]}" ]] || hold 'Post-update package UID changed.'
  if [[ "$role" == phone ]]; then
    PHONE_APK_PATH=$path PHONE_APK_HASH=$built PHONE_UPDATE_TIME=$after
  fi
  current=$(app_processes "$serial" "$role") || hold 'Cannot observe post-update processes.'
  reconcile_role "$role" "$serial" "$current"
  while read -r pid ticks name; do
    [[ -n "$pid" ]] || continue
    key="$role,$pid"
    # Reconciliation requires owned removal events plus stable absence, not KILL alone.
    [[ ! -v "LIVE[$key]" ]] || hold 'Old app process survived the update.'
  done <<< "$old"
  LIFECYCLE_ACTION=
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

# Observation records are retained before EVENTS can be normalized or replaced.
# Only bounded copies of these typed records reach stdout; raw logcat stays in pipes.
observe_emit() {
  local record=$* bytes
  [[ ${#record} -le 512 && "$record" != *[[:cntrl:]]* ]] || return 1
  bytes=$(wc -c <"$SCRATCH/observed") || return 1
  (( bytes + ${#record} + 1 <= 1046528 )) || return 1
  printf '%s\n' "$record" >>"$SCRATCH/observed" || return 1
  printf '%s\n' "$record" >>"$SCRATCH/pending"
}

observe_flush() {
  (( ! OBS_OUTPUT_FAILED )) || return 1
  if ! timeout --kill-after=1s 2s cat "$SCRATCH/pending" >&"$OBS_PROTOCOL"; then
    OBS_OUTPUT_FAILED=1
    return 1
  fi
  : >"$SCRATCH/pending"
}

observe_retain() {
  local role=$1 hi=$2 records line bytes
  [[ -f "$SCRATCH/$role.events" ]] || return 0
  bytes=$(wc -c <"$SCRATCH/$role.events") || return 1
  (( bytes <= 262144 )) || return 1
  records=$(awk -v lo="${CURSOR[$role]:-0}" -v hi="$hi" 'NR > lo && NR <= hi' "$SCRATCH/$role.events") || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    observe_emit "RESULT $OBS_REQUEST $OBS_PHASE $role $line" || return 1
  done <<< "$records"
  CURSOR[$role]=$hi
}

observe_signal() {
  OBS_FAILED=1 OBS_ERROR=$2 OBS_PENDING_SIGNAL=$1
  # Even a signal before EXIT claims retirement must finish it before exiting.
  # Once claimed, nested signals only latch failure; no handler uses locals.
  if (( ! OBS_RETIRING && ! OBS_LAUNCHING )); then
    observe_cleanup || OBS_FAILED=1
    exit "$OBS_FAILED"
  fi
}

observe_launch_done() {
  # Register every ownership entry before a signal can enter cleanup.
  OBS_LAUNCHING=0
  if (( OBS_PENDING_SIGNAL )); then exit "$OBS_PENDING_SIGNAL"; fi
}

observe_retire_timer() {
  local pid=$OBS_TIMER deadline=$((SECONDS + 4)) forced=0 failed=0
  [[ -n "$pid" ]] || return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    OBS_ERROR='Observation timer exited before owned retirement.'
    wait "$pid" 2>/dev/null || :
    OBS_TIMER=
    return 1
  fi
  kill -TERM "$pid" 2>/dev/null || :
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      if (( forced )); then
        OBS_ERROR='Observation timer retirement is unproved.'
        return 1
      fi
      OBS_ERROR='Observation timer retirement exceeded its deadline.'
      forced=1
      kill -KILL "$pid" 2>/dev/null || :
      deadline=$((SECONDS + 1))
    fi
    sleep 0.05 || { failed=1; OBS_ERROR='Observation timer retirement wait failed.'; }
  done
  # Wait only after absence is established, so a stopped timer cannot block it.
  if ! wait "$pid" 2>/dev/null; then
    failed=1
    OBS_ERROR='Observation timer did not acknowledge cancellation.'
  fi
  if kill -0 "$pid" 2>/dev/null; then
    OBS_ERROR='Observation timer retirement is unproved.'
    return 1
  fi
  OBS_TIMER=
  return "$((forced || failed))"
}

observe_arm() {
  local seconds=$1 owner=$$ remaining ready deadline=$((SECONDS + $1))
  (( deadline <= OBS_EXPIRES )) || deadline=$OBS_EXPIRES
  OBS_LIMIT=$deadline
  observe_retire_timer || hold "$OBS_ERROR"
  remaining=$((deadline - SECONDS))
  (( seconds > 0 && remaining > 0 )) || hold 'Observation lifetime expired.'
  # A builtin timed read avoids an unowned sleep descendant. The second deadline
  # bounds an unresponsive shell; ordinary cleanup retains and retires its children.
  OBS_LAUNCHING=1
  (
    trap 'exit 0' INT TERM HUP
    # Only this child writes readiness, after cancellation is operative. Its
    # separate pipe cannot be consumed by the timer's own deadline read.
    if printf '%s\n' "$BASHPID" >&"$OBS_TIMER_READY"; then
      remaining=$((deadline - SECONDS))
      if (( remaining > 0 )); then
        IFS= read -r -t "$remaining" -u "$OBS_CLOCK" _ || :
      fi
    fi
    kill -TERM "$owner" 2>/dev/null || exit 0
    IFS= read -r -t 20 -u "$OBS_CLOCK" _ || :
    kill -KILL "$owner" 2>/dev/null || :
  ) >/dev/null 2>&1 &
  OBS_TIMER=$!
  observe_launch_done
  # Ownership is registered before this fallible wait. Retirement and readiness
  # consume the phase's original absolute budget, including immediately queued input.
  remaining=$((deadline - SECONDS))
  (( remaining > 0 )) || hold 'Observation timer readiness deadline expired.'
  IFS= read -r -t "$remaining" -u "$OBS_TIMER_READY" ready \
    || hold 'Observation timer readiness failed or expired.'
  [[ "$ready" == "$OBS_TIMER" ]] && kill -0 "$OBS_TIMER" 2>/dev/null \
    || hold 'Observation timer readiness is unproved.'
  (( SECONDS < deadline )) || hold 'Observation timer readiness deadline expired.'
}

observe_identity() {
  local role=$1 serial=$2 name characteristics features uid packages size config qualifier boot
  name=$(adb_on "$serial" emu avd name | tr -d '\r' | sed '/^OK$/d; /^$/d') \
    || hold 'Cannot recheck actual AVD identity.'
  characteristics=$(adb_on "$serial" shell -n getprop ro.build.characteristics | tr -d '\r') \
    || hold 'Cannot recheck actual device role.'
  features=$(adb_on "$serial" shell -n pm list features | tr -d '\r') \
    || hold 'Cannot recheck device features.'
  [[ ${#name} -le 128 && -n "$characteristics" && ${#characteristics} -le 128 && ${#features} -le 65536 \
    && "$name$characteristics${features//$'\n'/}" != *[[:cntrl:]]* ]] \
    || hold 'Device identity metadata exceeds observation bounds.'
  if [[ "$role" == phone ]]; then
    [[ "$name" == "$PHONE_AVD" && ",$characteristics," != *,watch,* \
      && $'\n'"$features"$'\n' == *$'\nfeature:android.hardware.telephony\n'* \
      && "$features" != *android.hardware.type.watch* ]] || hold 'Canonical phone identity changed.'
    qualifier=phone
  else
    [[ "$name" == "$WEAR_AVD" && ",$characteristics," == *,watch,* \
      && $'\n'"$features"$'\n' == *$'\nfeature:android.hardware.type.watch\n'* ]] \
      || hold 'Selected Wear identity changed.'
    size=$(adb_on "$serial" shell -n wm size | tr -d '\r') || hold 'Cannot prove Wear geometry.'
    [[ "$size" == "Physical size: ${OBS_SIZE}x${OBS_SIZE}" ]] || hold 'Wear size is overridden or unexpected.'
    config=$(adb_on "$serial" shell -n cmd activity get-config | tr -d '\r') || hold 'Cannot prove Wear shape.'
    [[ ${#config} -le 16384 && "${config//$'\n'/}" != *[[:cntrl:]]* ]] || hold 'Wear configuration is malformed.'
    qualifier=$(printf '%s\n' "$config" | awk '$1 == "config:" { if (NF != 2) exit 1; count++; value=$2 }
      END { if (count != 1) exit 1; print value }') || hold 'Wear configuration is ambiguous.'
    [[ "-$qualifier-" == *-watch-* && "-$qualifier-" == *-"$OBS_SHAPE"-* ]] || hold 'Wear shape differs from selection.'
    if [[ "$OBS_SHAPE" == round ]]; then
      [[ "-$qualifier-" != *-notround-* ]] || hold 'Wear shape is ambiguous.'
    else
      [[ "-$qualifier-" != *-round-* ]] || hold 'Wear shape is ambiguous.'
    fi
    qualifier="$OBS_SIZE-$OBS_SHAPE"
  fi
  uid=$(package_uid "$serial") || hold 'Cannot recheck exact installed package UID.'
  [[ "$uid" == "${UIDS[$role]}" ]] || hold 'Exact installed package UID changed.'
  (( uid % 100000 >= 10000 && uid % 100000 <= 19999 )) || hold 'Package UID is not an ordinary app UID.'
  packages=$(adb_on "$serial" shell -n cmd package list packages -U --uid "$uid" | tr -d '\r') \
    || hold 'Cannot exclude shared UID ownership.'
  [[ "$packages" == "package:$APP_ID uid:$uid" ]] || hold 'Installed UID ownership is ambiguous.'
  boot=$(adb_on "$serial" shell -n cat /proc/sys/kernel/random/boot_id | tr -d '\r') \
    || hold 'Cannot recheck boot identity.'
  [[ "$boot" == "${BOOT[$role]}" ]] || hold 'Device rebooted during observation.'
  observe_emit "IDENTITY $OBS_REQUEST $OBS_PHASE $role $name $serial $qualifier $uid ${BOOT[$role]}" \
    || hold 'Cannot retain device identity.'
}

observe_boundary() {
  local role serial
  for role in phone wear; do
    if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
    observe_identity "$role" "$serial"
    reconcile_role "$role" "$serial"
    observe_identity "$role" "$serial"
    barrier "$role" "$serial"
  done
}

observe_read() {
  local char remaining
  OBS_INPUT=
  while :; do
    remaining=$((OBS_LIMIT - SECONDS))
    (( remaining > 0 )) || hold 'Observation input deadline expired.'
    # NUL is the delimiter, so it produces an empty character and is rejected,
    # rather than silently disappearing as it does with ordinary Bash read.
    IFS= read -r -n 1 -d '' -t "$remaining" char || hold 'Observation input ended or expired without typed close.'
    (( SECONDS < OBS_LIMIT )) || hold 'Observation input deadline expired.'
    [[ "$char" != $'\n' ]] || return 0
    [[ "$char" == [A-Z0-9\ ] && ${#OBS_INPUT} -lt 16 ]] || hold 'Malformed or oversized observation control.'
    OBS_INPUT+="$char"
  done
}

observe_cleanup() {
  # Before this claim, a nested handler completes retirement before it exits.
  # After it, handlers cannot exit, including before local initialization.
  if (( OBS_RETIRING )); then return "$OBS_FAILED"; fi
  OBS_RETIRING=1
  local role pid deadline=$((SECONDS + 4)) alive status forced=0 retired=1 lines
  OBS_PHASE=retirement
  # Acknowledged CLOSE lets the complete projector exit normally. All other
  # exits are losses, and their final GAP remains part of the retained result.
  for pid in "${MONITORS[@]}"; do
    [[ "${OBS_CLOSED[$pid]:-0}" == 1 && ( "$pid" == "${PROJECTORS[phone]:-}" || "$pid" == "${PROJECTORS[wear]:-}" ) ]] \
      || kill "$pid" 2>/dev/null || :
  done
  for role in phone wear; do
    [[ ! -v "PRODUCERS[$role]" ]] || kill -TERM -- "-${PRODUCERS[$role]}" 2>/dev/null || :
  done
  while :; do
    alive=0
    for pid in "${MONITORS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then alive=1; fi
    done
    for role in phone wear; do
      if [[ -v "PRODUCERS[$role]" ]] && kill -0 -- "-${PRODUCERS[$role]}" 2>/dev/null; then alive=1; fi
    done
    (( alive )) || break
    if (( SECONDS >= deadline )); then
      if (( forced )); then
        OBS_FAILED=1 OBS_ERROR='Owned monitor absence is unproved.'
        break
      fi
      OBS_FAILED=1 OBS_ERROR='Owned monitor retirement exceeded its deadline.'
      forced=1
      for pid in "${MONITORS[@]}"; do kill -KILL "$pid" 2>/dev/null || :; done
      for role in phone wear; do
        [[ ! -v "PRODUCERS[$role]" ]] || kill -KILL -- "-${PRODUCERS[$role]}" 2>/dev/null || :
      done
      deadline=$((SECONDS + 1))
    fi
    sleep 0.05 || OBS_FAILED=1
  done
  for role in phone wear; do
    status=1
    for pid in "${PRODUCERS[$role]:-}" "${PROJECTORS[$role]:-}"; do
      [[ -n "$pid" ]] || continue
      # Never enter an unbounded wait while an owned child is still present.
      if kill -0 "$pid" 2>/dev/null || { [[ "$pid" == "${PRODUCERS[$role]:-}" ]] && kill -0 -- "-$pid" 2>/dev/null; }; then
        OBS_FAILED=1 retired=0 OBS_ERROR='Owned monitor absence is unproved.'
        continue
      fi
      if wait "$pid" 2>/dev/null; then
        if [[ "$pid" == "${PROJECTORS[$role]:-}" ]]; then status=0; fi
      fi
      if kill -0 "$pid" 2>/dev/null || { [[ "$pid" == "${PRODUCERS[$role]:-}" ]] && kill -0 -- "-$pid" 2>/dev/null; }; then
        OBS_FAILED=1 retired=0 OBS_ERROR='Owned monitor absence is unproved.'
      else
        observe_emit "RETIRED $OBS_REQUEST $OBS_PHASE $role $pid" || OBS_FAILED=1
      fi
    done
    if [[ "${OBS_CLOSED[${PROJECTORS[$role]:-missing}]:-0}" != 1 || "$status" != 0 ]]; then
      OBS_FAILED=1
      [[ -n "$OBS_ERROR" ]] || OBS_ERROR='Projector ended without acknowledged close.'
    fi
    if [[ -f "$SCRATCH/$role.events" ]]; then
      if lines=$(wc -l <"$SCRATCH/$role.events"); then
        observe_retain "$role" "$lines" || OBS_FAILED=1
      else
        OBS_FAILED=1
      fi
    fi
  done
  if (( OBS_EXIT_STATUS != 0 || ! OBS_COMPLETE )); then
    OBS_FAILED=1
    [[ -n "$OBS_ERROR" ]] || OBS_ERROR='Observation failed before explicit close.'
  fi
  observe_flush || OBS_FAILED=1
  observe_retire_timer || OBS_FAILED=1
  [[ -z "$OBS_TIMER" ]] || retired=0
  if [[ -n "$OBS_CLOCK" ]] && ! exec {OBS_CLOCK}>&-; then OBS_FAILED=1; fi
  if [[ -n "$OBS_TIMER_READY" ]] && ! exec {OBS_TIMER_READY}>&-; then OBS_FAILED=1; fi
  # Keep recovery pipes and records whenever an owned tree or timer may survive.
  # The timer is now absent, so bound the existing removal like stdout copies.
  if (( retired )); then
    timeout --kill-after=1s 2s rm -rf -- "$SCRATCH" || OBS_FAILED=1
  fi
  if (( SECONDS >= OBS_LIMIT )); then
    OBS_FAILED=1
    [[ -n "$OBS_ERROR" ]] || OBS_ERROR='Observation deadline expired during retirement.'
  fi
  # Terminal records fit the reserved output allowance even if scratch is retained.
  if (( ! OBS_FAILED )); then
    # A blocked consumer cannot keep completion, or this foreground process, alive.
    timeout --kill-after=1s 2s cat <<<"COMPLETE $OBS_REQUEST OBSERVATION_ONLY" >&"$OBS_PROTOCOL" || OBS_FAILED=1
    if (( SECONDS >= OBS_LIMIT )); then
      OBS_FAILED=1
      [[ -n "$OBS_ERROR" ]] || OBS_ERROR='Observation deadline expired during terminal delivery.'
    fi
  fi
  if (( OBS_FAILED )); then
    timeout --kill-after=1s 2s cat <<<"FAILED $OBS_REQUEST ${OBS_ERROR:-Observation output, cleanup or retirement failed.}" >&"$OBS_PROTOCOL" || :
    timeout --kill-after=1s 2s cat <<<"HOLD: ${OBS_ERROR:-Observation output, cleanup or retirement failed.}" >&2 || :
  fi
  return "$OBS_FAILED"
}

observe() {
  OBS_EXPIRES=$((SECONDS + 180)) OBS_LIMIT=$((SECONDS + 60))
  [[ $# == 1 ]] || hold 'Observe requires exactly one target: 384-round or 360-notround.'
  case "$1" in
    384-round) WEAR_AVD=wardpulse_wear_round_api36_1; OBS_SIZE=384 OBS_SHAPE=round ;;
    360-notround) WEAR_AVD=wardpulse_wear_square_api36_1; OBS_SIZE=360 OBS_SHAPE=notround ;;
    *) hold 'Unsupported observation target.' ;;
  esac
  [[ "${WEAR_SERIAL:-}" =~ ^[a-zA-Z0-9._:-]+$ ]] || hold 'Observe requires an explicit existing WEAR_SERIAL.'
  require_sdk_root
  require_executable "$ADB"
  local tool role serial snapshot pid ticks name key command request component
  for tool in timeout awk cat mktemp mkfifo sort sed tr wc grep rm sleep; do
    command -v "$tool" >/dev/null || hold "Required host executable not found: $tool"
  done
  (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) \
    || hold 'Bash 4.4 or newer is required.'
  export LC_ALL=C
  SCRATCH=$(timeout --kill-after=1s 5s mktemp -d)
  OBSERVING=1 OBS_PHASE=startup
  # Signals entering before the cleanup claim also retire before they can exit.
  # The conditional call prevents errexit from abandoning the retirement pass;
  # each fallible cleanup operation retains failure and lets retirement continue.
  trap 'OBS_EXIT_STATUS=$?; observe_cleanup || OBS_FAILED=1; exit "$OBS_FAILED"' EXIT
  trap 'observe_signal 130 "Observation interrupted by a signal or expired deadline."' INT
  trap 'observe_signal 143 "Observation interrupted by a signal or expired deadline."' TERM HUP
  trap 'observe_signal 1 "Observation output closed."' PIPE
  # EXIT/signal cleanup must retain protocol stdout inside diagnostic redirects.
  exec {OBS_PROTOCOL}>&1 || hold 'Cannot preserve observation protocol output.'
  : >"$SCRATCH/observed"
  : >"$SCRATCH/pending"
  mkfifo "$SCRATCH/deadline.pipe" "$SCRATCH/deadline-ready.pipe"
  exec {OBS_CLOCK}<>"$SCRATCH/deadline.pipe"
  exec {OBS_TIMER_READY}<>"$SCRATCH/deadline-ready.pipe"
  observe_arm "$((OBS_LIMIT - SECONDS))"
  resolve_devices
  for role in phone wear; do
    if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
    UIDS[$role]=$(package_uid "$serial") || hold 'Cannot establish exact installed package UID.'
    snapshot=$(processes "$serial" "$role") || hold 'Cannot establish boot/process identities.'
    BOOT[$role]=${snapshot%%$'\n'*}
    BOOT[$role]=${BOOT[$role]#boot }
    [[ "${BOOT[$role]}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || hold 'Missing boot identity.'
    observe_identity "$role" "$serial"
  done
  start_monitor phone "$PHONE_SERIAL"
  start_monitor wear "$WEAR_SERIAL"
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
  observe_boundary
  observe_emit 'READY 0 OBSERVATION_ONLY' || hold 'Cannot retain observation readiness.'
  observe_flush || hold 'Observation output blocked or closed.'
  while :; do
    OBS_PHASE=input
    observe_arm 15
    observe_read
    [[ "$OBS_INPUT" =~ ^(DRAIN|CLOSE|STOP\ PHONE|STOP\ WEAR|LAUNCH\ PHONE|LAUNCH\ WEAR)\ ([1-9]|[12][0-9]|3[0-2])$ ]] \
      || hold 'Expected DRAIN, CLOSE, STOP PHONE/WEAR or LAUNCH PHONE/WEAR with request number 1..32.'
    command=${BASH_REMATCH[1]} request=${BASH_REMATCH[2]}
    (( request == OBS_REQUEST + 1 )) || hold 'Observation request numbers must be consecutive.'
    OBS_REQUEST=$request OBS_PHASE=operation
    case "$command" in
      STOP\ *) observe_arm 15 ;;
      *) observe_arm 30 ;;
    esac
    observe_boundary
    case "$command" in
      'STOP PHONE'|'LAUNCH PHONE')
        role=phone serial=$PHONE_SERIAL component="$APP_ID/.MainActivity" ;;
      'STOP WEAR'|'LAUNCH WEAR')
        role=wear serial=$WEAR_SERIAL component="$APP_ID/app.wardpulse.wear.MainActivity" ;;
    esac
    case "$command" in
      STOP\ *)
        stop_app "$role" "$serial" optional >&2
        LIFECYCLE_ACTION="$role:death" ;;
      LAUNCH\ *)
        launch_app "$role" "$serial" "$component" >&2
        LIFECYCLE_ACTION="$role:start" ;;
    esac
    case "$command" in
      STOP\ *|LAUNCH\ *)
        observe_boundary
        LIFECYCLE_ACTION= ;;
    esac
    (( SECONDS < OBS_LIMIT )) || hold 'Observation operation exceeded its deadline.'
    if [[ "$command" == CLOSE ]]; then
      OBS_PHASE=closing
      for role in phone wear; do
        if [[ "$role" == phone ]]; then serial=$PHONE_SERIAL; else serial=$WEAR_SERIAL; fi
        observe_identity "$role" "$serial"
        reconcile_role "$role" "$serial"
        barrier "$role" "$serial" close
      done
      (( SECONDS < OBS_LIMIT )) || hold 'Observation closing exceeded its deadline.'
      OBS_COMPLETE=1
      return
    fi
    observe_emit "ACK $OBS_REQUEST $command" || hold 'Cannot retain observation acknowledgment.'
    observe_flush || hold 'Observation output blocked or closed.'
    (( SECONDS < OBS_LIMIT )) || hold 'Observation operation exceeded its deadline.'
  done
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

declare -A BOOT=() OLD=() RUNNING=() CURSOR=() UIDS=() LIVE=() START_TICKS=() KILLED=()
declare -A PRODUCERS=() PROJECTORS=() OBS_CLOSE=() OBS_CLOSED=()
MONITORS=()
SCRATCH= DEVICE_SCRATCH= EVENTS= BASELINE= BASELINE_METADATA= OBSERVER=
READER_HOST= READER_DEVICE_PID=
READER_STAGE_ACTIVE=0 READER_BEFORE_PHONE=
LIFECYCLE_ACTION=
PHONE_APK_PATH= PHONE_APK_HASH= PHONE_UPDATE_TIME=
SEQUENCE=0 RETAINING=0 DELIVERING=0 FRESH_RECEIPT=0 FRESH_PUBLICATION=0
RETENTION_DEADLINE=0 LAST_OBSERVATION=0 LEDGER_READY=0 SENDER_COVERED=0
PHONE_ACTIVITY=0 WORK_ACTIVITY=0
OBSERVING=0 OBS_REQUEST=0 OBS_COMPLETE=0 OBS_LIMIT=0 OBS_EXPIRES=0
OBS_OUTPUT_FAILED=0 OBS_PROTOCOL=1
OBS_LAUNCHING=0 OBS_PENDING_SIGNAL=0
OBS_RETIRING=0 OBS_FAILED=0 OBS_EXIT_STATUS=0
OBS_TIMER= OBS_CLOCK= OBS_TIMER_READY= OBS_PHASE= OBS_ERROR= OBS_INPUT= OBS_SIZE= OBS_SHAPE=

case "${1:-}" in
  prepare) prepare ;;
  verify) verify ;;
  observe) shift; observe "$@" ;;
  *)
    printf 'Usage: %s prepare|verify|observe 384-round|360-notround\n' "$0" >&2
    exit 2
    ;;
esac
