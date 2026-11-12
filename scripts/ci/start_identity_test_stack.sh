#!/usr/bin/env bash
set -euo pipefail
umask 077
python3 scripts/ci/native_identity_stack.py start
