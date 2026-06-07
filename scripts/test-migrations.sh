#!/usr/bin/env bash
# Smoke-test the migrations + seed against a plain Postgres, without the full
# Supabase stack. Useful in CI or when the Supabase CLI / Docker isn't handy.
#
# It creates a throwaway database, installs minimal Supabase `auth` stubs
# (auth.users, auth.uid(), the anon/authenticated/service_role roles), then
# applies every migration in order followed by seed.sql. Any error aborts.
#
# Connection comes from standard libpq env vars (override as needed):
#   PGHOST (default 127.0.0.1)  PGPORT (default 5432)
#   PGUSER (default postgres)   PGPASSWORD
#
# Usage:
#   ./scripts/test-migrations.sh
#   PGPORT=55432 ./scripts/test-migrations.sh
set -euo pipefail

cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
TESTDB="${TESTDB:-mathetes_migration_test}"

admin() { psql -v ON_ERROR_STOP=1 -d postgres -q "$@"; }
run()   { psql -v ON_ERROR_STOP=1 -d "$TESTDB" -q "$@"; }

echo "Resetting database $TESTDB on $PGHOST:$PGPORT ..."
admin -c "drop database if exists $TESTDB;"
admin -c "create database $TESTDB;"

echo "Installing auth stubs ..."
run -f supabase/tests/auth_stubs.sql

for m in supabase/migrations/*.sql; do
  echo "  apply $(basename "$m")"
  run -f "$m"
done

echo "  apply seed.sql"
run -f supabase/seed.sql

echo "OK: all migrations + seed applied cleanly."
