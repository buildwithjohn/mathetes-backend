#!/usr/bin/env bash
# Apply the Mathetes schema to a hosted/remote Postgres (e.g. Supabase).
#
# Unlike the local test harness, this does NOT install auth stubs: hosted
# Supabase already provides the `auth` schema, `auth.uid()`, and the anon/
# authenticated/service_role roles. It applies migrations in order, then loads
# the full KJV. The dev sample seed (placeholder WOTD/devotional) is applied
# only with WITH_SAMPLE=1.
#
# Usage:
#   scripts/deploy-cloud.sh "postgresql://user:pass@host:5432/postgres"
#   DATABASE_URL="postgresql://..." scripts/deploy-cloud.sh
#   WITH_SAMPLE=1 scripts/deploy-cloud.sh "postgresql://..."
#
# Tip: use the SESSION-mode connection (port 5432 on the pooler, or the direct
# db.<ref>.supabase.co:5432 host). The transaction pooler (6543) does not
# support COPY / multi-statement migrations.
set -euo pipefail
cd "$(dirname "$0")/.."

URL="${1:-${DATABASE_URL:-}}"
if [ -z "$URL" ]; then
  echo "usage: scripts/deploy-cloud.sh <postgres-connection-url>" >&2
  exit 1
fi

PSQL=(psql "$URL" -v ON_ERROR_STOP=1)

echo "==> Applying migrations"
for m in supabase/migrations/*.sql; do
  echo "    $(basename "$m")"
  "${PSQL[@]}" -q -f "$m"
done

echo "==> Loading full KJV (supabase/seed/kjv.sql)"
"${PSQL[@]}" -q -f supabase/seed/kjv.sql

if [ "${WITH_SAMPLE:-0}" = "1" ]; then
  echo "==> Applying dev sample seed (WITH_SAMPLE=1)"
  "${PSQL[@]}" -q -f supabase/seed.sql
fi

echo "==> Verifying"
"${PSQL[@]}" -At \
  -c "select 'parishes='||count(*) from public.parishes" \
  -c "select 'houses='||count(*) from public.houses" \
  -c "select 'bible_books='||count(*) from public.bible_books" \
  -c "select 'bible_verses='||count(*) from public.bible_verses" \
  -c "select 'tables='||count(*) from pg_tables where schemaname='public'"

echo "Done."
