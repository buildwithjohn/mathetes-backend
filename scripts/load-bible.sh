#!/usr/bin/env bash
# Load a translation's full text (supabase/seed/<code>.sql) into the database.
# The 0030 migration must already be applied (it seeds the version row + 66
# books that the seed joins onto). Pass one or more lowercase codes; with no
# args, loads all non-KJV public-domain versions.
#
#   ./scripts/load-bible.sh web bsb asv     # specific
#   ./scripts/load-bible.sh                 # all of web bsb asv
#
# Connection via libpq env vars (PGHOST/PGPORT/PGUSER/PGPASSWORD), same defaults
# as load-kjv.sh (local Supabase db on 54322).
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
DB="${PGDATABASE:-postgres}"

codes=("$@")
if [ ${#codes[@]} -eq 0 ]; then codes=(web bsb asv); fi

for code in "${codes[@]}"; do
  f="supabase/seed/${code}.sql"
  [ -f "$f" ] || { echo "no such seed: $f" >&2; exit 1; }
  echo "Loading $code into $PGHOST:$PGPORT/$DB ..."
  psql -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

psql -d "$DB" -At -c "select code || '=' || count(*)
  from public.bible_versions ver
  join public.bible_books b on b.version_id = ver.id
  join public.bible_chapters c on c.book_id = b.id
  join public.bible_verses v on v.chapter_id = c.id
  group by code order by code"
echo "Bible load complete."
