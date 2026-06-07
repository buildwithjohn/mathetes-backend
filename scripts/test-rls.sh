#!/usr/bin/env bash
# RLS regression suite. Builds a throwaway database (auth stubs + all migrations
# + seed) and runs supabase/tests/rls_test.sql, which asserts the pastoral
# guardrails and isolation rules. Any failed assertion aborts with non-zero.
#
# Connection via libpq env vars (PGHOST/PGPORT/PGUSER/PGPASSWORD).
# Usage:  PGPORT=55432 ./scripts/test-rls.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
TESTDB="${TESTDB:-mathetes_rls_test}"

admin() { psql -v ON_ERROR_STOP=1 -d postgres -q "$@"; }
run()   { psql -v ON_ERROR_STOP=1 -d "$TESTDB" -q "$@"; }

echo "Building $TESTDB on $PGHOST:$PGPORT ..."
admin -c "drop database if exists $TESTDB;"
admin -c "create database $TESTDB;"
run -f supabase/tests/auth_stubs.sql
for m in supabase/migrations/*.sql; do run -f "$m"; done
run -f supabase/seed.sql

echo "Running RLS assertions ..."
run -f supabase/tests/rls_test.sql

echo "RLS suite passed."
