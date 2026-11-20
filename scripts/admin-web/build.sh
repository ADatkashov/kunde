#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null; then
  sdk="$(mktemp -d)"
  trap 'rm -rf "$sdk"' EXIT
  git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git "$sdk/flutter"
  export PATH="$sdk/flutter/bin:$PATH"
fi

cd "$(dirname "$0")/../../mobile"
flutter pub get --enforce-lockfile
flutter build web --no-pub --no-web-resources-cdn --target lib/admin_rides_main.dart
