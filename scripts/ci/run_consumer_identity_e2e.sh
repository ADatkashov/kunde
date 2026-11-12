#!/usr/bin/env bash
set -euo pipefail
native_venv="$(mktemp -d "${RUNNER_TEMP:-/tmp}/kunde-native-python-XXXXXX")"
trap 'rm -rf "$native_venv"' EXIT
python3 -m venv "$native_venv"
"$native_venv/bin/pip" install --disable-pip-version-check --require-hashes --only-binary=:all: --no-deps -r scripts/ci/native-e2e-requirements.txt
"$native_venv/bin/python" scripts/ci/consumer_native_e2e.py
