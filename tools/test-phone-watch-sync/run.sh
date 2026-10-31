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
  if (( PRE_DEATH_DEADLINE )); then
    # Keep the existing five-second kill grace inside this phase's total bound,
    # with one additional tick for the integral SECONDS clock.
    local remaining=$((PRE_DEATH_DEADLINE - SECONDS - 6))
    (( remaining > 0 )) || hold 'Post-update PRE-DEATH evidence deadline expired; quiescence is unproved.'
    (( seconds <= remaining )) || seconds=$remaining
  fi
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
  local uid=${UIDS[$2]} observer= released=0
  [[ "$uid" =~ ^[1-9][0-9]{0,9}$ ]] && (( uid <= 2147483647 )) || return 1
  if [[ "$2" == phone && -n "$OBSERVER" ]]; then
    observer=$OBSERVER released=$OBSERVER_RELEASED
    [[ "$observer" =~ ^[1-9][0-9]*\ [1-9][0-9]*\ wardpulse-work-snapshot-[0-9]+$ &&
       "$released" =~ ^[01]$ ]] || return 1
  fi
  adb_on "$1" shell -n "uid=$uid observer=\"$observer\" released=$released" '
    set -eu
    observer_pid= observer_start= observer_name= retired=0
    if [ -n "$observer" ]; then read -r observer_pid observer_start observer_name <<EOF
$observer
EOF
    fi
    list() {
      raw=$(ps -A -o UID,PID,NAME) || exit 1
      [ "${#raw}" -le 1048576 ] || return 1
      records=$(printf "%s\n" "$raw" | awk -v uid="$uid" -v pid="$observer_pid" -v name="$observer_name" '\''
        function fail() { bad=1; exit 1 }
        NR == 1 { if (NF != 3 || $1 != "UID" || $2 != "PID" || $3 != "NAME") fail(); next }
        $1 == uid || (pid != "" && $2 == pid) {
          if ($1 != uid || $1 !~ /^[1-9][0-9]*$/ || NF != 3 || $0 ~ /[[:cntrl:]]/ ||
              ++rows > 128 || (bytes += length($0)+1) > 16384 ||
              $2 !~ /^[1-9][0-9]*$/ || length($2) > 10 || $2+0 > 2147483647 || seen[$2]++ ||
              length($3) > 128 || ($2 == pid ? $3 != name : $3 !~ /^app[.]wardpulse(:[a-zA-Z0-9_.]+)?$/)) fail()
          records[rows]=$2 " " $3
        }
        END { if (bad || !NR) exit 1; for (i=1; i<=rows; i++) print records[i] }
      '\'') || return 1
      [ -z "$records" ] || printf "%s\n" "$records" | sort
    }
    identities() {
      # Keep retirement state in this shell across both lists and traversals.
      for boundary in before after; do
        current=$(list) || return 1
        inventory= found=0
        while read -r pid name; do
          [ -n "$pid" ] || continue
          if [ "$pid" = "$observer_pid" ]; then
            [ "$retired" = 0 ] || return 1
            found=1
          fi
          start=$(awk '\''{ sub(/^.*\) /, ""); print $20 }'\'' "/proc/$pid/stat") || {
            [ "$released" = 1 ] && [ "$pid" = "$observer_pid" ] && [ ! -e "/proc/$pid" ] || return 1
            retired=1
            continue
          }
          printf "%s\n" "$start" | awk '\''
            NR != 1 || NF != 1 || $0 !~ /^[1-9][0-9]*$/ || length($0) > 20 ||
            (length($0) == 20 && ("x" $0) > "x18446744073709551615") { exit 1 }
          '\'' || return 1
          if [ "$pid" = "$observer_pid" ]; then
            [ "$start" = "$observer_start" ] || return 1
            [ "$released" = 0 ] || continue
          fi
          inventory="$inventory$pid $start $name
"
        done <<EOF
$current
EOF
        if [ "$released" = 1 ] && [ "$found" = 0 ]; then
          [ ! -e "/proc/$observer_pid" ] || return 1
          retired=1
        fi
        if [ "$boundary" = before ]; then before=$inventory
        else [ "$before" = "$inventory" ] || return 1; fi
      done
    }
    boot=$(cat /proc/sys/kernel/random/boot_id) || exit 1
    identities || exit 1
    first=$inventory
    identities || exit 1
    [ "$first" = "$inventory" ]
    [ "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" ]
    printf "boot %s\n" "$boot"
    if [ "$released" = 1 ] && [ "$retired" = 0 ]; then first="$first$observer
"; fi
    printf "%s" "$first" | sort
  ' | tr -d '\r'
}

app_processes() {
  local snapshot
  snapshot=$(processes "$1" "$2") || hold 'Process identity read failed or raced.'
  [[ "${snapshot%%$'\n'*}" == "boot ${BOOT[$2]}" ]] || hold 'Device rebooted during measurement.'
  local identities
  identities=$(printf '%s\n' "$snapshot" | sed '1d')
  # Inventory accounts separately for the attested reader after GO, including retirement.
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
  if (( PRE_DEATH_DEADLINE && deadline >= PRE_DEATH_DEADLINE )); then deadline=$((PRE_DEATH_DEADLINE - 1)); fi
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
  # Summary bytes stay on Wear; emit only a complete digest after command success.
  # Completion lines also require a final newline from both SHA-256 and ADB.
  local digest
  digest=$(
    {
      adb_on "$WEAR_SERIAL" shell -n '
        set -o pipefail || exit 1
        { run-as '"$APP_ID"' sha256sum shared_prefs/watch_summary.xml && printf "DONE\n"; } |
          LC_ALL=C awk '\''
            NR == 1 && length($1) == 64 && $1 ~ /^[0-9a-f]+$/ &&
                $0 == $1 "  shared_prefs/watch_summary.xml" { digest=$1; next }
            NR == 2 && $0 == "DONE" { complete=1; next }
            { bad=1; exit 1 }
            END { if (bad || !complete || NR != 2) exit 1; print digest }
          '\''
      ' 2>/dev/null && printf 'DONE\n'
    } | LC_ALL=C awk '
      NR == 1 && length($0) == 64 && /^[0-9a-f]+$/ { digest=$0; next }
      NR == 2 && $0 == "DONE" { complete=1; next }
      { bad=1; exit 1 }
      END { if (bad || !complete || NR != 2) exit 1; print digest }
    '
  ) || return 1
  printf '%s\n' "$digest"
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
  local label=$1 phone_live=$2 metadata uid phase=0 ids states
  (( ! PRE_DEATH_DEADLINE )) || phase=1
  uid=$(package_uid "$PHONE_SERIAL")
  [[ "$uid" == "${UIDS[phone]}" ]] || hold 'Native scheduling package UID changed.'
  metadata=$(adb_on "$PHONE_SERIAL" shell -n '
    set -o pipefail || exit 1
    (
      if [ '"$phase"' = 1 ]; then
        printf "WP_CLOCK %s %s %s\n" "$(cat /proc/sys/kernel/random/boot_id)" \
          "$(cut -d " " -f1 /proc/uptime)" "$(date +%s%3N)" || exit 1
      fi
      dumpsys jobscheduler app.wardpulse 2>&1 && printf "\nWP_DONE\n"
    ) | awk -v uid='"$uid"' -v quiet='"$phase"' -v boot='"${BOOT[phone]}"' '\''
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
    function duration(value, sign, result, digits, unit, scale, last) {
      if (value == "none" || value == "0") return 0
      if (length(value) > 64 || value !~ /^[+-]/) fail()
      sign=substr(value, 1, 1); value=substr(value, 2); last=86400001
      if (!length(value)) fail()
      while (length(value)) {
        if (!match(value, /^[0-9]+/)) fail()
        digits=substr(value, 1, RLENGTH); value=substr(value, RLENGTH+1)
        if (!number(digits, 2147483647)) fail()
        unit=substr(value, 1, 1)
        if (substr(value, 1, 2) == "ms") { scale=1; value=substr(value, 3) }
        else {
          if (unit == "d") scale=86400000
          else if (unit == "h") scale=3600000
          else if (unit == "m") scale=60000
          else if (unit == "s") scale=1000
          else fail()
          value=substr(value, 2)
        }
        if (scale >= last) fail()
        last=scale; result+=digits*scale
        if (result > 9007199254740991) fail()
      }
      return sign == "+" ? result : 0
    }
    function flush() {
      if (block && (services != 1 || constraints != 1)) fail()
      if (block && relevant) {
        if (!owned || !tagged || !wm || network != 1 ||
            seen_job[id]++ || ++jobs > 64) fail()
        inventory[jobs]="native-job " id " 1 1"
        if (quiet) {
          if (readiness != 1 || runtime != 1) fail()
          eligibility[jobs]="native-ready " id " " (safe && timing == 1) " " delay
        }
      }
      block=relevant=owned=tagged=services=wm=constraints=network=0
      readiness=runtime=safe=timing=delay=0
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
      if (quiet && (clock != 1 || pending_header != 1 || active_header != 1 || idle_header != 1)) fail()
      complete=1; next
    }
    quiet && /^WP_CLOCK / {
      if (NR != 1 || NF != 4 || $2 != boot || $3 !~ /^[0-9]+[.][0-9][0-9]$/ ||
          length($3) > 16 || $4 !~ /^[0-9]+$/ || length($4) != 13 || clock++) fail()
      clock_line="native-clock begin " $3 " " $4; next
    }
    quiet && /^Pending queue:$/ {
      if (!closed || pending_header++ || active_header || idle_header) fail()
      section="pending"; next
    }
    quiet && /^Active jobs:$/ {
      if (pending_header != 1 || active_header++ || idle_header) fail()
      section="active"; next
    }
    quiet && /^Idle contexts \([0-9]+\):$/ {
      if (active_header != 1 || idle_header++) fail()
      section=""; next
    }
    quiet && section == "pending" {
      if (NF) {
        if ($0 == "  None") { if (pending_none++ || pending_body) fail() }
        else { if (pending_none) fail(); pending_body++ }
      }
      next
    }
    quiet && section == "active" {
      if (NF) {
        if ($0 == "  N/A") { if (active_none++ || active_body) fail() }
        else { if (active_none) fail(); active_body++ }
      }
      next
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
        if ($i == "TIMING_DELAY") timing++
      }
      if (hex_mask($NF) != expected_mask) fail()
      next
    }
    quiet && block && relevant && $1 == "Run" && $2 == "time:" {
      if (runtime++ || NF != 6 || $3 !~ /^earliest=.+,$/ || $4 != "latest=none," ||
          $5 != "original" || $6 != "latest=none") fail()
      value=$3; sub(/^earliest=/, "", value); sub(/,$/, "", value)
      delay=duration(value); next
    }
    quiet && block && relevant && $1 == "Ready:" {
      if (readiness++ || NF != 9 || $2 !~ /^(true|false)$/ || $3 !~ /^\(job=(true|false)$/ ||
          $4 !~ /^user=(true|false)$/ || $5 !~ /^!restricted=(true|false)$/ ||
          $6 !~ /^!pending=(true|false)$/ || $7 !~ /^!active=(true|false)$/ ||
          $8 !~ /^!backingup=(true|false)$/ || $9 !~ /^comp=(true|false)\)$/) fail()
      safe=($2 == "false" && $3 == "(job=false" && $4 == "user=true" &&
        $5 == "!restricted=true" && $6 == "!pending=true" && $7 == "!active=true" &&
        $8 == "!backingup=true" && $9 == "comp=true)")
      next
    }
    /^[[:space:]]*(Service|Required[[:space:]]+constraints)/ {
      if (block || index($0, "app.wardpulse/")) fail()
    }
    END {
      if (bad || !complete || !jobs) exit 1
      for (i=1; i<=jobs; i++) {
        print inventory[i]
        if (quiet) print eligibility[i]
      }
      print "native-count", jobs
      if (quiet) {
        # A complete UID-filtered active section may be blank or contain only N/A.
        print "native-queues", (pending_none == 1 && !pending_body && !active_body)
        print clock_line
      }
    }
  '\''' 2>/dev/null) || hold 'Cannot obtain bounded native scheduling metadata.'
  [[ $(printf '%s' "$metadata" | wc -c) -le 8192 ]] || hold 'Native scheduling metadata exceeds its safe bound.'
  if (( phase )); then
    ids=$(awk '$1 == "native-job" { printf "%s ", $2 }' <<< "$metadata")
    # One bounded shell queries every registered ID in its verified user/namespace.
    # The command can report combinations; only the exclusive waiting state is quiet.
    states=$(adb_on "$PHONE_SERIAL" shell -n '
      set -eu
      for id in '"$ids"'; do
        state=$(cmd jobscheduler get-job-state -u '"$((uid / 100000))"' \
          -n androidx.work.systemjobscheduler app.wardpulse "$id") || exit 1
        printf "WP_STATE %s %s\n" "$id" "$state"
      done
      printf "WP_CLOCK %s %s %s\n" "$(cat /proc/sys/kernel/random/boot_id)" \
        "$(cut -d " " -f1 /proc/uptime)" "$(date +%s%3N)"
    ' 2>/dev/null | tr -d '\r' | awk -v boot="${BOOT[phone]}" '
      function fail() { bad=1; exit 1 }
      $1 == "WP_STATE" {
        if (complete || NF < 3 || NF > 8 || $2 !~ /^[0-9]+$/ || length($2) > 10 ||
            $2+0 > 2147483647 || seen[$2]++ || ++rows > 64) fail()
        for (i=3; i<=NF; i++) {
          if ($i !~ /^(pending|active|user-stopped|backing-up|no-component|ready|waiting)$/ ||
              token[$2, $i]++ || ($i == "waiting" && NF != 3)) fail()
        }
        print "native-state", $2, (NF == 3 && $3 == "waiting"); next
      }
      $1 == "WP_CLOCK" {
        if (NF != 4 || $2 != boot || $3 !~ /^[0-9]+[.][0-9][0-9]$/ || length($3) > 16 ||
            $4 !~ /^[0-9]+$/ || length($4) != 13 || complete++) fail()
        print "native-clock end", $3, $4; next
      }
      { fail() }
      END { if (bad || !complete || !rows) exit 1 }
    ') || hold 'Current native execution state is unknown or raced.'
    metadata+=$'\n'"$states"
  fi
  printf '%s\n' "$metadata" >"$SCRATCH/native.current"
  awk -v previous_native="$SCRATCH/native.previous" -v previous_work="$SCRATCH/work.previous" \
    -v current_native="$SCRATCH/native.current" -v activity="$((PHONE_ACTIVITY - WORK_ACTIVITY))" \
    -v phone_live="$phone_live" -v stage="$label" -v phase="$phase" '
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
      } else if (phase && ($1 == "native-ready" || $1 == "native-state")) {
        if (($1 == "native-ready" ? NF != 4 : NF != 3) || $2 !~ /^[0-9]+$/ ||
            $3 !~ /^[01]$/ || detail[$1, $2]++ ||
            ($1 == "native-ready" && $4 !~ /^[0-9]+$/)) fail()
      } else if (phase && $1 == "native-queues") {
        if (NF != 2 || $2 !~ /^[01]$/ || queues++) fail()
      } else if (phase && $1 == "native-clock") {
        if (NF != 4 || $2 !~ /^(begin|end)$/ || clock[$2]++ ||
            $3 !~ /^[0-9]+[.][0-9][0-9]$/ || $4 !~ /^[0-9]+$/ || length($4) != 13) fail()
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
    END {
      if (bad || count != 1 || jobs+0 != expected) exit 1
      if (phase) {
        if (queues != 1 || clock["begin"] != 1 || clock["end"] != 1) exit 1
        for (id in job) if (detail["native-ready", id] != 1 || detail["native-state", id] != 1) exit 1
        for (key in detail) {
          split(key, pair, SUBSEP)
          if (!(pair[2] in job)) exit 1
        }
      }
    }
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
          (( ! INITIAL_DEATHS )) || hold 'Replacement/background process started after PRE-DEATH handoff.'
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

reader_diagnostic() {
  # A synchronous owned timeout reaps each small writer. A blocked diagnostic
  # sink must neither stall the reader/cleanup nor silently turn evidence into PASS.
  timeout --kill-after=0.1s 0.1s "$BASH" -c 'printf "$@" >&2' bash "$@" \
    || READER_DIAG_OUTPUT_FAILED=1
}

reader_stderr_collect() {
  local LC_ALL=C chunk status remaining deadline=$((SECONDS + 7)) stderr_seen=0 run_as=0 load=0 line_start=1
  # Drain continuously in bounded chunks, including after a category is found.
  # Only these three fixed tokens can reach the diagnostic file; raw bytes stay
  # in the FIFO and this child's bounded memory. Its lifetime matches the wrapper.
  while :; do
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || return 1
    chunk='' status=0
    IFS= read -r -t "$remaining" -n 256 chunk || status=$?
    if [[ -n "$chunk" ]] || (( status == 0 )); then
      if (( ! stderr_seen )); then printf 'OBSERVED\n'; stderr_seen=1; fi
      if (( line_start )); then
        case "$chunk" in
          'run-as: '*)
            if (( ! run_as )); then printf 'RUN_AS_REPORTED\n'; run_as=1; fi ;;
          'Error: Could not find class '*|'Error: Could not find or load main class '*|'CANNOT LINK EXECUTABLE '*)
            if (( ! load )); then printf 'LOAD_REPORTED\n'; load=1; fi ;;
        esac
      fi
      line_start=$(( ${#chunk} < 256 ))
    fi
    if (( status != 0 )); then
      (( status == 1 ))
      return
    fi
  done
}

reader_stderr() {
  local phase=$1 token record stderr_seen=0 run_as=0 load=0 category=UNOBSERVED
  # The owned collector writes at most three fixed lines. Read only that bound,
  # and never forward even an unexpected token from the private scratch file.
  for record in 1 2 3; do
    IFS= read -r -n 32 token || break
    case "$token" in
      OBSERVED) stderr_seen=1 ;;
      RUN_AS_REPORTED) run_as=1 ;;
      LOAD_REPORTED) load=1 ;;
    esac
  done <"$SCRATCH/reader.stderr.categories"
  if (( run_as && load )); then category=RUN_AS_AND_LOAD_REPORTED
  elif (( run_as )); then category=RUN_AS_REPORTED
  elif (( load )); then category=LOAD_REPORTED
  elif (( stderr_seen )); then category=UNCLASSIFIED; fi
  reader_diagnostic 'Reader stderr: phase=%s category=%s\n' "$phase" "$category"
}

work_snapshot() {
  local label=$1 apk pid ticks name header line output= end= rejection= reader_in reader_out reader_host
  local before_phone before_wear current phone_live=0 deadline=$((SECONDS + 8))
  local started read_status=0 read_outcome=line header_shape=complete wrapper_status diagnostic_status
  OBSERVER_RELEASED=0
  if (( RETAINING )); then check_separation "$label-entry"; fi
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  before_phone=$(app_processes "$PHONE_SERIAL" phone) || hold 'Pre-reader phone identity raced.'
  [[ -z "$before_phone" ]] || phone_live=1
  before_wear=$(app_processes "$WEAR_SERIAL" wear) || hold 'Pre-reader Wear identity raced.'
  apk=$(installed_apk "$PHONE_SERIAL")
  if (( RETAINING )); then check_separation "$label-before-reader"; fi
  # The existing reader/watchdog limits stay unchanged. Do not start a capture
  # that cannot fit inside the enclosing PRE-DEATH phase, including kill grace.
  if (( PRE_DEATH_DEADLINE )); then
    (( SECONDS + 9 < PRE_DEATH_DEADLINE )) \
      || hold 'Post-update PRE-DEATH evidence deadline cannot admit a complete Reader capture.'
  fi
  name="wardpulse-work-snapshot-$$"
  READER_STAGE_ACTIVE=1 READER_BEFORE_PHONE=$before_phone
  mkfifo "$SCRATCH/reader.stderr" 2>/dev/null || hold 'Cannot allocate reader diagnostic pipe.'
  # Open both ends before unlinking, so asynchronous startup cannot race path removal.
  if ! { exec {READER_STDERR_FD}<>"$SCRATCH/reader.stderr" \
      {READER_STDERR_DRAIN_FD}<"$SCRATCH/reader.stderr"; } 2>/dev/null; then
    hold 'Cannot open reader diagnostic descriptors.'
  fi
  rm -- "$SCRATCH/reader.stderr" 2>/dev/null || hold 'Cannot unlink reader diagnostic pipe.'
  if ! { : >"$SCRATCH/reader.stderr.categories"; } 2>/dev/null; then
    hold 'Cannot allocate sanitized reader diagnostics.'
  fi
  reader_stderr_collect <&"$READER_STDERR_DRAIN_FD" >"$SCRATCH/reader.stderr.categories" \
    {READER_STDERR_FD}>&- {READER_STDERR_DRAIN_FD}<&- &
  READER_DIAG_HOST=$!
  # This one ADB shell intentionally consumes GO from stdin, after identity verification.
  coproc WORK_READER { exec timeout --kill-after=1s 7s "$ADB" -s "$PHONE_SERIAL" shell -T \
    "run-as app.wardpulse env CLASSPATH=$DEVICE_SCRATCH/reader.dex app_process /system/bin --nice-name=$name WorkSnapshot ${UIDS[phone]} $apk" \
    2>&"$READER_STDERR_FD" {READER_STDERR_FD}>&- {READER_STDERR_DRAIN_FD}<&-; }
  reader_host=$! READER_HOST=$!
  [[ "$reader_host" =~ ^[0-9]+$ ]] || hold 'Reader host process is unavailable.'
  if [[ ! -v WORK_READER[0] || ! -v WORK_READER[1] ]]; then
    reader_stderr startup
    reader_diagnostic 'Reader header: outcome=unavailable elapsed_seconds=unknown content=unknown status=unknown\n'
    (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
    hold 'Reader host descriptors are unavailable.'
  fi
  exec {READER_OUTPUT_FD}<&"${WORK_READER[0]}" {READER_INPUT_FD}>&"${WORK_READER[1]}"
  reader_out=$READER_OUTPUT_FD reader_in=$READER_INPUT_FD
  exec {READER_STDERR_FD}>&- {READER_STDERR_DRAIN_FD}<&-
  READER_STDERR_FD='' READER_STDERR_DRAIN_FD=''
  started=$SECONDS
  IFS= read -r -t 2 -n 256 header <&"$reader_out" || read_status=$?
  if (( read_status != 0 )); then
    if (( read_status > 128 )); then read_outcome=timeout
    elif (( read_status == 1 )); then read_outcome=eof
    else read_outcome=error; fi
    header_shape=empty
    [[ -z "$header" ]] || header_shape=partial
  elif (( ${#header} == 256 )); then
    read_outcome=limit header_shape=bounded
  fi
  reader_diagnostic 'Reader header: outcome=%s elapsed_seconds=%s content=%s status=%s\n' \
    "$read_outcome" "$((SECONDS - started))" "$header_shape" "$read_status"
  reader_stderr startup
  (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
  [[ "$read_outcome" == line ]] || hold 'Reader DEX loading/UID/security handshake unavailable.'
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
  READER_INPUT_FD=
  OBSERVER_RELEASED=1
  # Only the exact, separately verified reader identity is excluded by app_processes.
  if (( RETAINING )); then check_separation "$label-reader-released"; fi
  while IFS= read -r -t 2 line <&"$reader_out"; do
    line=${line//$'\r'/}
    (( SECONDS < deadline && ${#output} < 16384 )) || hold 'Reader exceeded output/time bounds.'
    if [[ "$line" == 'HOLD '* ]]; then
      [[ "$line" =~ ^HOLD\ [A-Z_]+$ ]] || hold 'Malformed reader failure.'
      rejection=${line#HOLD }
      case "$rejection" in
        ORPHAN_SYSTEM_ID|FUTURE_SYSTEM_ID) break ;;
        *) hold "Work reader: $rejection" ;;
      esac
    fi
    if [[ "$line" == "END $pid $ticks" ]]; then end=1; break; fi
    [[ "$line" =~ ^(SCHEMA|SQLITE|TIME|MAPPINGS|WORK)\ [a-zA-Z0-9._:\ -]+$ ]] || hold 'Malformed or unrecognized reader output.'
    output+="$line"$'\n'
  done
  [[ "$end" == 1 || -n "$rejection" ]] || hold 'Partial reader evidence.'
  if IFS= read -r -t 1 line <&"$reader_out"; then hold 'Unexpected trailing reader output.'; fi
  exec {reader_out}<&-
  READER_OUTPUT_FD=
  wrapper_status=0
  wait "$reader_host" || wrapper_status=$?
  READER_HOST=
  reader_diagnostic 'Reader wrapper: phase=completion exit=%s\n' "$wrapper_status"
  diagnostic_status=0
  wait "$READER_DIAG_HOST" || diagnostic_status=$?
  READER_DIAG_HOST=
  reader_diagnostic 'Reader stderr collector: phase=completion exit=%s\n' "$diagnostic_status"
  reader_stderr completion
  (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
  if [[ -n "$rejection" ]]; then
    (( wrapper_status == 1 )) || hold 'Rejected reader process did not retire with its expected failure.'
  else
    (( wrapper_status == 0 )) || hold 'Reader process failed or did not retire normally.'
  fi
  (( diagnostic_status == 0 )) || hold 'Reader stderr collector failed or did not retire normally.'
  adb_on "$PHONE_SERIAL" shell -n "test ! -e /proc/$pid" || hold 'Reader PID is still live or reused.'
  READER_DEVICE_PID= OBSERVER=
  OBSERVER_RELEASED=0
  READER_STAGE_ACTIVE=0
  if (( RETAINING )); then check_separation "$label-reader-retired"; fi
  current=$(app_processes "$PHONE_SERIAL" phone) || hold 'Post-reader phone identity raced.'
  [[ "$current" == "$before_phone" ]] || hold 'Reader interval included phone activity.'
  current=$(app_processes "$WEAR_SERIAL" wear) || hold 'Post-reader Wear identity raced.'
  [[ "$current" == "$before_wear" ]] || hold 'Reader interval included Wear activity.'
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'App start/death/publication raced work observation.'
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Wear activity raced work observation.'
  printf '%s' "$output" >"$SCRATCH/work.current"
  reconcile_work "$label" "$rejection"
  [[ -z "$rejection" ]] || hold "Work reader: $rejection"
  if (( RETAINING )); then check_separation "$label-before-native"; fi
  native_jobs "$label" "$phone_live"
  if (( PRE_DEATH_DEADLINE )); then
    # Native queries are inside the same identity/event proof as the Reader.
    [[ $(package_uid "$PHONE_SERIAL") == "${UIDS[phone]}" &&
       $(package_uid "$WEAR_SERIAL") == "${UIDS[wear]}" ]] || hold 'PRE-DEATH package UID changed.'
    current=$(app_processes "$PHONE_SERIAL" phone) || hold 'Post-native phone identity raced.'
    [[ "$current" == "$before_phone" ]] || hold 'Phone identity changed across native observation.'
    current=$(app_processes "$WEAR_SERIAL" wear) || hold 'Post-native Wear identity raced.'
    [[ "$current" == "$before_wear" ]] || hold 'Wear identity changed across native observation.'
    barrier phone "$PHONE_SERIAL"
    [[ -z "$EVENTS" ]] || hold 'Phone activity raced native observation.'
    barrier wear "$WEAR_SERIAL"
    [[ -z "$EVENTS" ]] || hold 'Wear activity raced native observation.'
    (( SECONDS < PRE_DEATH_DEADLINE )) || hold 'Post-update PRE-DEATH evidence deadline expired.'
  fi
  if [[ "$label" == preflight ]]; then
    # Keep the narrow installed tuple visible for HOST binding after scratch cleanup.
    awk '$1 == "SCHEMA" || $1 == "SQLITE" || $1 == "MAPPINGS"' "$SCRATCH/work.current"
  fi
  # Advance the accepted pair only after logical AND native evidence reconcile.
  cp "$SCRATCH/work.current" "$SCRATCH/work.previous"
  cp "$SCRATCH/native.current" "$SCRATCH/native.previous"
  WORK_ACTIVITY=$PHONE_ACTIVITY
  printf 'Bounded logical/native work reconciled: %s\n' "$label"
}

reconcile_work() {
  local label=$1 rejection=${2:-}
  # Validate the protocol independently of the Java reader, then reconcile only
  # documented transitions. Activity permits possible enqueue/execution, not
  # arbitrary spec changes or a claim about all intermediate transitions.
  awk -v previous="$SCRATCH/work.previous" -v activity="$((PHONE_ACTIVITY - WORK_ACTIVITY))" \
    -v rejected="$rejection" '
    function fail() { bad=1; exit 1 }
    function same(x, y) { return ("x" x) == ("x" y) }
    function bounded_count(value) {
      return value ~ /^(0|[1-9][0-9]*)$/ && length(value) <= 10 && value+0 <= 2147483647
    }
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
      if (rejected || FNR != 1 || NF != 5 || $2 != "2.11.2" || $3 != 24 || $4 != "08b926448d86528e697981ddd30459f7" ||
          ($5 != "no_backup" && $5 != "databases") || schema++ || (oldschema && $0 != oldschema)) fail()
      next
    }
    $1 == "SQLITE" {
      source=$5; sub(/-alt[0-9]+$/, "", source)
      if (rejected || FNR != 2 || NF != 6 || ($2 != "3.44.3" && $2 != "3.44.4") ||
          $3 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ ||
          $4 !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ ||
          length(source) != 64 || source !~ /^[0-9a-f]+$/ || length($5) > 79 ||
          ($6 != "wal" && $6 != "delete") || sqlite++ || (oldsqlite && $0 != oldsqlite)) fail()
      next
    }
    $1 == "TIME" { if (rejected || FNR != 3 || NF != 2 || length($2) != 13 || $2 !~ /^[0-9]+$/ || time++) fail(); now=$2; next }
    $1 == "MAPPINGS" {
      if (FNR != (rejected ? 1 : 4) || NF != 6 || mappings++) fail()
      for (i=2;i<=6;i++) if (!bounded_count($i)) fail()
      if ($2 != $3+$4+$5+$6) fail()
      missing=$3; current=$4; future=$6; mapping_record=$0
      next
    }
    $1 == "WORK" {
      if (rejected || schema != 1 || sqlite != 1 || time != 1 || mappings != 1 || NF != 25 || ++rows > 32 || seen[$3]++ ||
          ($2 != "wardpulse.providerSync" && $2 != "wardpulse.recoveryWake") ||
          $3 !~ /^[0-9a-f-]+$/ || $4 !~ /^[0-5]$/ ||
          $5 != "dev.fluttercommunity.workmanager.BackgroundWorker") fail()
      for (i=6;i<=25;i++) if ($i !~ /^-?[0-9]+$/) fail()
      if (!bounded_count($14) || (!same($15, "-1") && !bounded_count($15))) fail()
      if ($15 >= 0) { if (job_seen[$15]++) fail(); mapped++ }
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
      if (bad || mappings != 1) exit 1
      if (rejected) {
        if (FNR != 1 || !((rejected == "ORPHAN_SYSTEM_ID" && missing > 0) ||
            (rejected == "FUTURE_SYSTEM_ID" && missing == 0 && future > 0))) exit 1
        print "Rejected mapping evidence: " mapping_record > "/dev/stderr"
        exit 0
      }
      if (schema != 1 || sqlite != 1 || time != 1 || periodic != 1 || missing != 0 || future != 0 ||
          mapped+0 != current) exit 1
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
  local phase=$1 started=$SECONDS finished current metadata phone
  [[ "$phase" =~ ^[a-z][a-z-]{0,63}$ ]] || hold 'Invalid retention observation phase.'
  if (( started >= RETENTION_DEADLINE || started - LAST_OBSERVATION >= 3 )); then
    hold "Retention timing: phase=$phase boundary=entry" \
      "total_expired=$((started >= RETENTION_DEADLINE)) gap_expired=$((started - LAST_OBSERVATION >= 3))" \
      "elapsed_seconds=$((started + 60 - RETENTION_DEADLINE)) remaining_seconds=$((RETENTION_DEADLINE - started))" \
      "age_seconds=$((started - LAST_OBSERVATION)) work_seconds=0."
  fi
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity/publication invalidated separation.'
  phone=$(app_processes "$PHONE_SERIAL" phone) || hold 'Phone process observation failed.'
  [[ -z "$phone" ]] || hold 'Phone app is no longer absent.'
  current=$(summary_hash) || hold 'Retention summary hash read failed.'
  metadata=$(summary_metadata) || hold 'Retention summary stat failed.'
  [[ "$current" == "$BASELINE" && "$metadata" == "$BASELINE_METADATA" ]] || hold 'Saved summary changed or was replaced during retention.'
  finished=$SECONDS
  if (( finished >= RETENTION_DEADLINE || finished - LAST_OBSERVATION >= 3 )); then
    hold "Retention timing: phase=$phase boundary=observation-work" \
      "total_expired=$((finished >= RETENTION_DEADLINE)) gap_expired=$((finished - LAST_OBSERVATION >= 3))" \
      "elapsed_seconds=$((finished + 60 - RETENTION_DEADLINE)) remaining_seconds=$((RETENTION_DEADLINE - finished))" \
      "age_seconds=$((finished - LAST_OBSERVATION)) entry_age_seconds=$((started - LAST_OBSERVATION)) work_seconds=$((finished - started))."
  fi
  LAST_OBSERVATION=$finished
}

stop_app() {
  local role=$1 serial=$2 required=$3 old current events= identity key pending
  local deadline=$((SECONDS + 15))
  # The foreground STOP owns one budget, including its surrounding boundaries.
  if (( OBSERVING && deadline > OBS_LIMIT )); then deadline=$OBS_LIMIT; fi
  if (( INITIAL_DEATHS )); then
    # The fresh scheduling exclusion must cover this entire original death budget,
    # including after the intervening Reader. Never reuse an expired quiet proof.
    (( deadline < INITIAL_DEATH_UNTIL )) || hold 'PRE-DEATH scheduling exclusion expired before intended death.'
  fi
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
    if (( RETAINING )) && [[ "$role" == wear ]]; then check_separation wear-death-loop; fi
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
      if (( RETAINING )) && [[ "$role" == wear ]]; then check_separation wear-death-complete; fi
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
    if (( RETAINING )); then check_separation "$role-launch-loop"; fi
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
  # Preserve the failure status and the Reader's existing cleanup budgets.
  local PRE_DEATH_DEADLINE=0
  local running stopped wrapper_state=unowned wrapper_exit=unknown wrapper_action=none cleanup_exit=unknown
  local device_retirement=unobserved uid_retirement=unobserved staging=absent descriptors=closed
  local diagnostic_action=none diagnostic_exit=unknown
  trap - EXIT
  if [[ -n "$READER_HOST" ]]; then
    # Inspect the owned job before any cleanup action. Only an already completed
    # child can supply an original exit status; a later TERM result is cleanup.
    running=$(jobs -pr) stopped=$(jobs -ps)
    if [[ $'\n'"$running"$'\n' == *$'\n'"$READER_HOST"$'\n'* ]]; then
      wrapper_state=active
    elif [[ $'\n'"$stopped"$'\n' == *$'\n'"$READER_HOST"$'\n'* ]]; then
      wrapper_state=stopped
    else
      wrapper_exit=0
      wait "$READER_HOST" 2>/dev/null || wrapper_exit=$?
      if (( wrapper_exit == 127 )); then wrapper_state=unknown wrapper_exit=unknown
      else wrapper_state=exited; fi
    fi
  fi
  reader_diagnostic 'Reader wrapper: phase=pre_cleanup state=%s exit=%s\n' "$wrapper_state" "$wrapper_exit"
  if [[ -n "$READER_DIAG_HOST" ]]; then reader_stderr pre_cleanup; fi
  if [[ "$wrapper_state" == active || "$wrapper_state" == stopped ]]; then
    wrapper_action=term_requested
    # Without job control, Bash may still list a stopped child as active. Resume
    # only this owned job so its timeout can forward TERM and retire its children.
    kill -CONT "$READER_HOST" 2>/dev/null || :
    kill "$READER_HOST" 2>/dev/null || wrapper_action=term_unavailable
    cleanup_exit=0
    wait "$READER_HOST" 2>/dev/null || cleanup_exit=$?
  fi
  READER_HOST=
  reader_diagnostic 'Reader wrapper: phase=cleanup action=%s wait_status=%s\n' "$wrapper_action" "$cleanup_exit"
  if [[ -n "$READER_INPUT_FD" ]] && ! exec {READER_INPUT_FD}>&-; then result=1 descriptors=failed; fi
  if [[ -n "$READER_OUTPUT_FD" ]] && ! exec {READER_OUTPUT_FD}<&-; then result=1 descriptors=failed; fi
  if [[ -n "$READER_STDERR_FD" ]] && ! exec {READER_STDERR_FD}>&-; then result=1 descriptors=failed; fi
  if [[ -n "$READER_STDERR_DRAIN_FD" ]] && ! exec {READER_STDERR_DRAIN_FD}<&-; then result=1 descriptors=failed; fi
  if [[ -n "$READER_DIAG_HOST" ]]; then
    running=$(jobs -pr) stopped=$(jobs -ps)
    if [[ $'\n'"$running"$'\n' == *$'\n'"$READER_DIAG_HOST"$'\n'* || \
          $'\n'"$stopped"$'\n' == *$'\n'"$READER_DIAG_HOST"$'\n'* ]]; then
      diagnostic_action=term_requested
      kill -CONT "$READER_DIAG_HOST" 2>/dev/null || :
      kill "$READER_DIAG_HOST" 2>/dev/null || diagnostic_action=term_unavailable
    fi
    diagnostic_exit=0
    wait "$READER_DIAG_HOST" 2>/dev/null || diagnostic_exit=$?
    READER_DIAG_HOST=
    reader_stderr post_cleanup
  fi
  reader_diagnostic 'Reader stderr collector: phase=cleanup action=%s wait_status=%s\n' \
    "$diagnostic_action" "$diagnostic_exit"
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
    if (( retired )); then device_retirement=absent; else device_retirement=unproved; fi
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
      uid_retirement=unproved
    else
      uid_retirement=reconciled
    fi
  fi
  if [[ -n "$DEVICE_SCRATCH" ]]; then
    staging=retained
    if (( retired )); then
      if remove_reader_staging; then staging=removed
      else
        printf 'HOLD: Owned device reader staging could not be removed.\n' >&2
        result=1 staging=failed
      fi
    fi
  fi
  (( ! READER_DIAG_OUTPUT_FAILED )) || result=1
  reader_diagnostic 'Reader cleanup: descriptors=%s device_pid=%s uid=%s staging=%s result=%s\n' \
    "$descriptors" "$device_retirement" "$uid_retirement" "$staging" "$result"
  for pid in "${MONITORS[@]}"; do kill "$pid" 2>/dev/null || :; done
  for pid in "${MONITORS[@]}"; do wait "$pid" 2>/dev/null || :; done
  [[ -z "$SCRATCH" ]] || rm -rf -- "$SCRATCH"
  (( ! READER_DIAG_OUTPUT_FAILED )) || result=1
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

  # One settling phase, never renewed. Failed/raced captures still HOLD; pacing
  # only separates fresh complete observations, without resetting either ledger.
  # Three matching quiet proofs over >=2 integral ticks corroborate stability.
  # Quiet also needs a current native timing exclusion of five minutes, covering
  # both 15s initial deaths and their intervening bounded Reader/native proof.
  # This is prospective evidence, not an explanation of the historical dispatch.
  PRE_DEATH_DEADLINE=$((SECONDS + 30))
  reader_diagnostic 'Post-update PRE-DEATH: phase=evidence bound_seconds=30\n'
  (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
  local predeath_phone predeath_wear predeath_phone_cursor predeath_wear_cursor predeath_counts
  local quiet_samples=0 quiet_since=0 quiet_work= quiet_native= quiet_phone= quiet_wear=
  local quiet_phone_cursor=0 quiet_wear_cursor=0 sample_work sample_native sample_started continuous
  while :; do
    sample_started=$SECONDS
    predeath_phone=$(app_processes "$PHONE_SERIAL" phone) || hold 'Post-update phone identity is unproved.'
    reconcile_role phone "$PHONE_SERIAL" "$predeath_phone"
    predeath_phone_cursor=${CURSOR[phone]}
    predeath_wear=$(app_processes "$WEAR_SERIAL" wear) || hold 'Post-update Wear identity is unproved.'
    reconcile_role wear "$WEAR_SERIAL" "$predeath_wear"
    predeath_wear_cursor=${CURSOR[wear]}
    work_snapshot post-update-pre-death
    reconcile_role phone "$PHONE_SERIAL" "$predeath_phone"
    reconcile_role wear "$WEAR_SERIAL" "$predeath_wear"
    continuous=1
    for role in phone wear; do
      if [[ "$role" == phone ]]; then snapshot=$predeath_phone_cursor; else snapshot=$predeath_wear_cursor; fi
      awk -v lo="$snapshot" -v hi="${CURSOR[$role]}" '
        NR > lo && NR <= hi && $1 != "MARK" { activity=1 }
        END { exit activity }
      ' "$SCRATCH/$role.events" || hold 'Activity crossed PRE-DEATH evidence; quiescence is unproved.'
      if (( quiet_samples )); then
        if [[ "$role" == phone ]]; then snapshot=$quiet_phone_cursor; else snapshot=$quiet_wear_cursor; fi
        if ! awk -v lo="$snapshot" -v hi="${CURSOR[$role]}" '
          NR > lo && NR <= hi && $1 != "MARK" { activity=1 }
          END { exit activity }
        ' "$SCRATCH/$role.events"; then continuous=0; fi
      fi
    done
    predeath_counts=$(awk -v native="$SCRATCH/native.current" -v age="$((SECONDS - sample_started + 1))" '
      FILENAME == native {
        if ($1 == "native-job") { jobs[$2]=1; count++ }
        if ($1 == "native-ready") { safe[$2]=$3; delay[$2]=$4 }
        if ($1 == "native-state") waiting[$2]=$3
        if ($1 == "native-queues") queues=$2
        if ($1 == "native-clock") { uptime[$2]=$3*1000; epoch[$2]=$4 }
        next
      }
      $1 == "TIME" { worktime=$2 }
      $1 == "WORK" {
        if ($4 == 1) running++
        if ($4 == 4) blocked++
        if ($4 == 0 || $4 == 1 || $4 == 4) {
          active++
          if ($15 >= 0 && ($15 in jobs)) matched[$15]++
          else unmatched_work++
          if ($17 == -1) unscheduled++
        }
      }
      END {
        elapsed=uptime["end"]-uptime["begin"]
        wall=epoch["end"]-epoch["begin"]
        skew=wall-elapsed; if (skew < 0) skew=-skew
        if (elapsed < 0 || elapsed > 30000 || wall < 0 || wall > 30000 || skew >= 1000 ||
            worktime > epoch["begin"] || epoch["begin"]-worktime > 30000) exit 1
        for (id in jobs) {
          if (matched[id] != 1) unmatched++
          # Subtract the complete same-device query interval and a conservative
          # host capture age; a Ready:false flag alone is never a quiet proof.
          if (safe[id] != 1 || waiting[id] != 1 || delay[id]-elapsed < 300000+age*1000) eligible++
        }
        quiet=queues == 1 && active > 0 && !running && !blocked && !unscheduled &&
          !unmatched_work && !unmatched && !eligible
        printf "quiet=%d owned_running=%d owned_blocked=%d owned_unscheduled=%d native_jobs=%d unmatched_native=%d unsafe_native=%d", \
          quiet, running, blocked, unscheduled, count, unmatched, eligible
      }
    ' "$SCRATCH/native.current" "$SCRATCH/work.current") || hold 'PRE-DEATH scheduling clocks are unknown or inconsistent.'
    sample_work=$(awk '$1 == "WORK"' "$SCRATCH/work.current")
    sample_native=$(awk '$1 == "native-job"' "$SCRATCH/native.current" | sort)
    (( SECONDS < PRE_DEATH_DEADLINE )) || hold 'Post-update PRE-DEATH evidence deadline expired; quiescence is unproved.'
    if [[ "$predeath_counts" == quiet=1\ * ]]; then
      if (( quiet_samples && continuous )) && [[ "$sample_work" == "$quiet_work" && "$sample_native" == "$quiet_native" &&
          "$predeath_phone" == "$quiet_phone" && "$predeath_wear" == "$quiet_wear" ]]; then
        quiet_samples=$((quiet_samples + 1))
      else
        quiet_samples=1 quiet_since=$SECONDS
      fi
      quiet_work=$sample_work quiet_native=$sample_native quiet_phone=$predeath_phone quiet_wear=$predeath_wear
      quiet_phone_cursor=${CURSOR[phone]} quiet_wear_cursor=${CURSOR[wear]}
      if (( quiet_samples >= 3 && SECONDS - quiet_since >= 2 )); then
        reader_diagnostic 'Post-update PRE-DEATH: phase=quiet-handoff samples=%s window_seconds=%s %s\n' \
          "$quiet_samples" "$((SECONDS - quiet_since))" "$predeath_counts"
        (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
        (( SECONDS < PRE_DEATH_DEADLINE )) || hold 'Post-update PRE-DEATH handoff deadline expired.'
        INITIAL_DEATH_UNTIL=$((sample_started + 300))
        INITIAL_DEATHS=1 PRE_DEATH_DEADLINE=0
        break
      fi
    else
      quiet_samples=0
    fi
    reader_diagnostic 'Post-update PRE-DEATH: phase=settling samples=%s %s\n' "$quiet_samples" "$predeath_counts"
    (( ! READER_DIAG_OUTPUT_FAILED )) || exit 1
    # Pacing is not evidence. Every next iteration repeats all logical, native,
    # identity and event proofs within the original thirty-second phase.
    sleep 1
  done

  stop_app wear "$WEAR_SERIAL" optional
  work_snapshot after-initial-wear-death
  stop_app phone "$PHONE_SERIAL" optional
  work_snapshot after-initial-phone-death
  # Both boundaries precede all delivery launches. Queued publication remains
  # distinct from the REQUIRED fresh Wear TYPE_CHANGED/save callback.
  barrier phone "$PHONE_SERIAL"
  barrier wear "$WEAR_SERIAL"
  FRESH_RECEIPT=0 FRESH_PUBLICATION=0 DELIVERING=1 INITIAL_DEATHS=0
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
  check_separation retention-start
  work_snapshot after-retention-phone-death
  check_separation after-retention-phone-death
  stop_app wear "$WEAR_SERIAL" required
  work_snapshot after-retention-wear-death
  check_separation after-retention-wear-death
  launch_app wear "$WEAR_SERIAL" "$APP_ID/app.wardpulse.wear.MainActivity"
  work_snapshot after-retention-wear-launch
  check_separation after-retention-wear-launch
  # SECONDS is integral: eleven ticks guarantee at least ten elapsed seconds.
  local until=$((SECONDS + 11)) after
  while (( SECONDS < until )); do
    check_separation retention-window
    barrier wear "$WEAR_SERIAL"
    [[ -z "$EVENTS" ]] || hold 'New Wear process/callback invalidated retention.'
    snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Cannot observe retained Wear process.'
    [[ "$snapshot" == "${RUNNING[wear]}" ]] || hold 'Wear identity changed during retention.'
    sleep 0.2
  done
  after=$(wait_for_stable_summary)
  check_separation retention-stable-summary
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Late callback/process activity invalidated retention.'
  [[ "$BASELINE" == "$after" ]] || hold 'Saved Wear summary changed after actual restart.'
  work_snapshot final
  check_separation final-work
  verify_sender_identity
  remove_reader_staging || hold 'Owned reader staging cleanup failed.'
  check_separation final-reader-cleanup
  reconcile_role phone "$PHONE_SERIAL"
  barrier phone "$PHONE_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Phone activity raced final preservation evidence.'
  reconcile_role wear "$WEAR_SERIAL"
  barrier wear "$WEAR_SERIAL"
  [[ -z "$EVENTS" ]] || hold 'Wear activity raced final preservation evidence.'
  snapshot=$(app_processes "$WEAR_SERIAL" wear) || hold 'Final Wear process observation failed.'
  [[ "$snapshot" == "${RUNNING[wear]}" ]] || hold 'Wear identity changed before completion.'
  check_separation retention-complete
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
OBSERVER_RELEASED=0
READER_HOST= READER_DEVICE_PID=
READER_STAGE_ACTIVE=0 READER_BEFORE_PHONE=
READER_INPUT_FD='' READER_OUTPUT_FD='' READER_STDERR_FD='' READER_STDERR_DRAIN_FD=''
READER_DIAG_HOST=
READER_DIAG_OUTPUT_FAILED=0
LIFECYCLE_ACTION=
PHONE_APK_PATH= PHONE_APK_HASH= PHONE_UPDATE_TIME=
SEQUENCE=0 RETAINING=0 DELIVERING=0 FRESH_RECEIPT=0 FRESH_PUBLICATION=0
INITIAL_DEATHS=0 INITIAL_DEATH_UNTIL=0
RETENTION_DEADLINE=0 LAST_OBSERVATION=0 LEDGER_READY=0 SENDER_COVERED=0
PHONE_ACTIVITY=0 WORK_ACTIVITY=0
PRE_DEATH_DEADLINE=0
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
