#!/usr/bin/env bash
# TASK-056 local restore drill: synthetic data only, throwaway PostgreSQL cluster, unix socket only.
# Applies Flyway SQL migrations in order, loads synthetic rows, takes pg_dump -Fc, restores into a
# fresh database, then compares schema and per-table row fingerprints. A negative check proves the
# fingerprint detects tampering. This is NOT production backup/PITR evidence (no region, KMS,
# retention or RTO/RPO; see docs/engineering-foundation/restore-drill.md).
set -euo pipefail

PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATIONS="$REPO/backend/src/main/resources/db/migration"
if [ "$(id -u)" = "0" ]; then
  echo "Run as a non-root user (initdb refuses root); e.g. runuser -u postgres -- $0" >&2
  exit 2
fi
WORK="$(mktemp -d)"
trap '"$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
SOCK="$WORK/sock"; mkdir -p "$SOCK"
PSQL=("$PG_BIN/psql" -h "$SOCK" -p 54329 -U drill -v ON_ERROR_STOP=1 -X -q -At)

"$PG_BIN/initdb" -D "$WORK/data" -U drill --auth=trust >/dev/null
"$PG_BIN/pg_ctl" -D "$WORK/data" -w -o "-c listen_addresses= -c unix_socket_directories=$SOCK -p 54329" \
  -l "$WORK/pg.log" start >/dev/null
"$PG_BIN/createdb" -h "$SOCK" -p 54329 -U drill source

fingerprint() { # $1 = database; prints "schema.table|count|md5" for every user table
  "${PSQL[@]}" -d "$1" <<'SQL'
DO $$ DECLARE r record; c bigint; h text;
BEGIN
  CREATE TEMP TABLE fp(t text, n bigint, h text);
  FOR r IN SELECT schemaname, tablename FROM pg_tables
           WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2 LOOP
    EXECUTE format('SELECT count(*), coalesce(md5(string_agg(x::text, E''\n'' ORDER BY x::text)), '''') FROM %I.%I x',
                   r.schemaname, r.tablename) INTO c, h;
    INSERT INTO fp VALUES (r.schemaname||'.'||r.tablename, c, h);
  END LOOP;
  CREATE TEMP TABLE fp_out AS SELECT * FROM fp;
END $$;
SELECT t||'|'||n||'|'||h FROM fp_out ORDER BY t;
SQL
}

# Structure comparison from the catalogs. A raw pg_dump -s diff is not used: it carries a random
# \\restrict token and re-deparses CHECK expressions after restore (same meaning, different text).
structure() { # $1 = database
  "${PSQL[@]}" -d "$1" <<'SQL'
SELECT 'col|'||table_schema||'.'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||coalesce(column_default,'')
  FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema')
UNION ALL
SELECT 'con|'||n.nspname||'.'||c.relname||'|'||o.conname||'|'||o.contype::text
  FROM pg_constraint o JOIN pg_class c ON c.oid=o.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
UNION ALL
SELECT 'idx|'||schemaname||'.'||tablename||'|'||indexname FROM pg_indexes
  WHERE schemaname NOT IN ('pg_catalog','information_schema')
ORDER BY 1;
SQL
}

for f in $(ls "$MIGRATIONS"/V*.sql | sort -V); do
  "${PSQL[@]}" -d source -f "$f"
done

"${PSQL[@]}" -d source <<'SQL'
INSERT INTO marketplace.categories (id, code, name_ru, name_kk, name_en, status, published_at)
VALUES ('00000000-0000-0000-0000-0000000000a1','synthetic-root','Синтетика','Синтетика','Synthetic','PUBLISHED',now()),
       ('00000000-0000-0000-0000-0000000000a2','synthetic-draft','Черновик','Қараша','Draft','DRAFT',NULL);
INSERT INTO marketplace.offerings (id, category_id, kind, name_ru, name_kk, status, published_at)
VALUES ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','SERVICE','Тест','Сынақ','PUBLISHED',now());
SQL

fingerprint source > "$WORK/source.fp"
"$PG_BIN/pg_dump" -h "$SOCK" -p 54329 -U drill -Fc -d source -f "$WORK/source.dump"
structure source > "$WORK/source.schema"

"$PG_BIN/createdb" -h "$SOCK" -p 54329 -U drill restored
"$PG_BIN/pg_restore" -h "$SOCK" -p 54329 -U drill --exit-on-error -d restored "$WORK/source.dump"
fingerprint restored > "$WORK/restored.fp"
structure restored > "$WORK/restored.schema"

diff -u "$WORK/source.schema" "$WORK/restored.schema" || { echo "FAIL: structure differs after restore"; exit 1; }
diff -u "$WORK/source.fp" "$WORK/restored.fp" || { echo "FAIL: row fingerprints differ after restore"; exit 1; }
[ "$(grep -c '^marketplace.offerings|1|' "$WORK/restored.fp")" = "1" ] || { echo "FAIL: synthetic offering missing"; exit 1; }
echo "PASS: schema and $(wc -l < "$WORK/restored.fp") table fingerprints identical after restore"

# Negative check: a tampered restore must be detected.
"${PSQL[@]}" -d restored -c "UPDATE marketplace.categories SET name_en='tampered' WHERE code='synthetic-root'"
fingerprint restored > "$WORK/tampered.fp"
if diff -q "$WORK/source.fp" "$WORK/tampered.fp" >/dev/null; then
  echo "FAIL: tampering was not detected"; exit 1
fi
echo "PASS: tampering detected by fingerprint comparison"
