#!/usr/bin/env bash
# Owner-run, LOCAL only. Creates a DEV release keystore outside the repository and prints
# the GitHub secret names to set. Back the keystore up (password manager / encrypted storage):
# losing it means APK updates can no longer be installed over the old app.
set -euo pipefail
out="${1:-$HOME/kunde-dev-release.jks}"
[ -e "$out" ] && { echo "refusing to overwrite $out" >&2; exit 1; }
read -r -s -p "Keystore/key password (>=12 chars): " pw; echo
keytool -genkeypair -v -keystore "$out" -storetype PKCS12 -alias kunde-dev \
  -keyalg RSA -keysize 4096 -validity 9125 -storepass "$pw" -keypass "$pw" \
  -dname "CN=KUNDE DEV, O=KUNDE, C=KZ"
cat <<MSG
Keystore: $out   (BACK IT UP; never commit it)
Set repository secrets (gh secret set NAME) :
  ANDROID_KEYSTORE_BASE64   = $(printf 'base64 -w0 %s' "$out")   (run it and paste the output)
  ANDROID_KEYSTORE_PASSWORD = the password you typed
  ANDROID_KEY_ALIAS         = kunde-dev
  ANDROID_KEY_PASSWORD      = the password you typed
MSG
