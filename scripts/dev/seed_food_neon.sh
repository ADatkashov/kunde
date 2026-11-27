#!/usr/bin/env bash
# Loads synthetic Food restaurants and menus into the DEV Neon database (see seed_food_neon.sql).
# DEV ONLY. The connection string comes from the environment and is never stored in the repository:
#   KUNDE_DEV_DATABASE_URL='postgresql://...'  KUNDE_SEED_CONFIRM_DEV=yes  scripts/dev/seed_food_neon.sh
set -euo pipefail

: "${KUNDE_DEV_DATABASE_URL:?set KUNDE_DEV_DATABASE_URL to the DEV Neon connection string}"
if [ "${KUNDE_SEED_CONFIRM_DEV:-}" != "yes" ]; then
  echo "Refusing to run: set KUNDE_SEED_CONFIRM_DEV=yes to confirm this is the DEV database (never PROD)." >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
psql "$KUNDE_DEV_DATABASE_URL" -v ON_ERROR_STOP=1 --single-transaction -f "$here/seed_food_neon.sql"
