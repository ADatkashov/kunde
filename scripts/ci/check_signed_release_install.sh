#!/usr/bin/env bash
set -euo pipefail

report=reports/release-install
adb shell getprop ro.product.cpu.abilist | tr -d '\r' | tee "$report/device-abis.txt"
if ! grep -qw arm64-v8a "$report/device-abis.txt"; then
  printf '{"status":"BLOCKED","reason":"Emulator lacks ARM64 compatibility"}\n' > "$report/status.json"
  exit 1
fi
install_and_start() {
  local name="$1" package="$2"
  printf '{"status":"RUNNING","apk":"%s"}\n' "$name" > "$report/status.json"
  adb install "$RUNNER_TEMP/releases/$name/$name.apk" | tee "$report/$name-install.txt"
  grep -qx Success "$report/$name-install.txt"
  adb shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$package" \
    | tee "$report/$name-launch.txt"
  grep -q '^Status: ok' "$report/$name-launch.txt"
  sleep 3
  adb shell pidof "$package" | grep -q '[0-9]'
  adb exec-out screencap -p > "$report/$name.png"
  adb shell am force-stop "$package"
}
install_and_start KUNDE-dev-release com.example.kunde_mobile
install_and_start KUNDE-Partner-dev-release com.kunde.kunde_partner
install_and_start KUNDE-executor-dev-release com.kunde.executor
install_and_start KUNDE-admin-dev-release com.kunde.admin
printf '{"status":"PASSED","installedAndLaunched":4}\n' > "$report/status.json"
