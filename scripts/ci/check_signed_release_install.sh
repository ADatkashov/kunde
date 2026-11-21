#!/usr/bin/env bash
set -euo pipefail

report=reports/release-install
adb shell getprop ro.product.cpu.abilist | tr -d '\r' | tee "$report/device-abis.txt"
if ! grep -qw arm64-v8a "$report/device-abis.txt"; then
  printf '{"status":"BLOCKED","reason":"Emulator lacks ARM64 compatibility"}\n' > "$report/status.json"
  exit 1
fi
install_and_start() {
  local name="$1" package="$2" activity="$3"
  if ! adb install "$RUNNER_TEMP/releases/$name/$name.apk" | tee "$report/$name-install.txt" ||
     ! grep -qx Success "$report/$name-install.txt" ||
     ! adb shell pm path "$package" | grep -q '^package:'; then
    printf 'INSTALL_FAILED\n' > "$report/$name-result.txt"
    return 1
  fi
  adb logcat -b crash -c
  if ! adb shell am start -W -n "$package/$activity" | tee "$report/$name-launch.txt" ||
     ! grep -q '^Status: ok' "$report/$name-launch.txt"; then
    printf 'LAUNCH_FAILED\n' > "$report/$name-result.txt"
    return 1
  fi
  sleep 5
  adb exec-out screencap -p > "$report/$name.png"
  if ! adb shell pidof "$package" | grep -q '[0-9]'; then
    adb logcat -b crash -d -t 150 > "$report/$name-crash.txt"
    adb shell dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity' > "$report/$name-foreground.txt" || true
    printf 'PROCESS_EXITED\n' > "$report/$name-result.txt"
    return 1
  fi
  adb shell am force-stop "$package"
  printf 'PASSED\n' > "$report/$name-result.txt"
}

passed=0
for spec in \
  "KUNDE-dev-release com.example.kunde_mobile com.example.kunde_mobile.MainActivity" \
  "KUNDE-Partner-dev-release com.kunde.kunde_partner com.kunde.kunde_partner.MainActivity" \
  "KUNDE-executor-dev-release com.kunde.executor com.example.kunde_mobile.MainActivity" \
  "KUNDE-admin-dev-release com.kunde.admin com.example.kunde_mobile.MainActivity"; do
  read -r name package activity <<< "$spec"
  if install_and_start "$name" "$package" "$activity"; then
    passed=$((passed + 1))
  fi
done
if [ "$passed" -ne 4 ]; then
  printf '{"status":"FAILED","installedAndLaunched":%d}\n' "$passed" > "$report/status.json"
  exit 1
fi
printf '{"status":"PASSED","installedAndLaunched":4}\n' > "$report/status.json"
