#!/usr/bin/env bash
# Load the full KJV (supabase/seed/kjv.sql) into the database. Run once after a
# reset; the 0003_bible.sql migration must already be applied (it seeds the KJV
# version row and the 66 books this data joins onto).
#
# Local Supabase default connection is used unless libpq env vars override it.
#   PGHOST (default 127.0.0.1)  PGPORT (default 54322, the supabase db port)
#   PGUSER (default postgres)   PGPASSWORD (default postgres)
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
DB="${PGDATABASE:-postgres}"

echo "Loading full KJV into $PGHOST:$PGPORT/$DB ..."
psql -v ON_ERROR_STOP=1 -d "$DB" -f supabase/seed/kjv.sql

psql -d "$DB" -At -c "select 'verses=' || count(*) from public.bible_verses" \
  -c "select 'chapters=' || count(*) from public.bible_chapters where verse_count > 0"
echo "KJV load complete."
