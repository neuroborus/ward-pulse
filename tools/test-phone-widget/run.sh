#!/usr/bin/env bash
set -euo pipefail
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
classes_dir=$(mktemp -d)
trap 'rm -rf "$classes_dir"' EXIT
javac -d "$classes_dir" \
  "$repository_root/apps/phone_flutter/android/app/src/main/java/app/wardpulse/PhoneWidgetLayout.java" \
  "$repository_root/apps/phone_flutter/android/app/src/main/java/app/wardpulse/DashboardLaunchRequest.java" \
  "$repository_root/tools/test-phone-widget/PhoneWidgetTest.java"
java -cp "$classes_dir" app.wardpulse.PhoneWidgetTest
