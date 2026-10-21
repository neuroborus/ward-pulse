#!/usr/bin/env bash
set -euo pipefail
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
classes_dir=$(mktemp -d)
trap 'rm -rf "$classes_dir"' EXIT
javac -d "$classes_dir" \
  "$repository_root/apps/phone_flutter/plugins/ward_pulse_watch_sync/android/src/main/java/app/wardpulse/watchsync/ConnectionCacheEngine.java" \
  "$repository_root/tools/test-phone-cache/ConnectionCacheEngineTest.java"
java -cp "$classes_dir" app.wardpulse.watchsync.ConnectionCacheEngineTest
