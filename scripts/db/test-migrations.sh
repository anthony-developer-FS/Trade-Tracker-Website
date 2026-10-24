#!/usr/bin/env bash
# Applies every migration to a throwaway local Postgres (with Supabase stubs)
# and runs the smoke test. Needs Postgres 15+ binaries on PATH or in
# /usr/lib/postgresql/<version>/bin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
WORK="$(mktemp -d)"
PORT="${PORT:-54329}"

cleanup() {
  "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"$PG_BIN/initdb" -D "$WORK/data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null

PSQL=(psql -h "$WORK" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -f "$ROOT/scripts/db/supabase_stubs.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "Applying $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f "$ROOT/supabase/tests/smoke_test.sql"
