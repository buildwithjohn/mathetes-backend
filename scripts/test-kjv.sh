#!/usr/bin/env bash
# Verify the full KJV import: build a fresh DB (auth stubs + migrations + dev
# seed), load supabase/seed/kjv.sql, and assert the canonical counts. Aborts
# non-zero on any mismatch.
#
# Connection via libpq env vars (PGHOST/PGPORT/PGUSER/PGPASSWORD).
# Usage:  PGPORT=55432 ./scripts/test-kjv.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
TESTDB="${TESTDB:-mathetes_kjv_test}"

admin() { psql -v ON_ERROR_STOP=1 -d postgres -q "$@"; }
run()   { psql -v ON_ERROR_STOP=1 -d "$TESTDB" -q "$@"; }

echo "Building $TESTDB on $PGHOST:$PGPORT ..."
admin -c "drop database if exists $TESTDB;"
admin -c "create database $TESTDB;"
run -f supabase/tests/auth_stubs.sql
for m in supabase/migrations/*.sql; do run -f "$m"; done
run -f supabase/seed.sql

echo "Loading full KJV ..."
run -f supabase/seed/kjv.sql

echo "Asserting counts ..."
run <<'SQL'
do $$
declare v int; c int; j int; p int;
begin
  select count(*) into v from public.bible_verses;
  select count(*) into c from public.bible_chapters;
  select count(*) into j from public.bible_verses bv
    join public.bible_chapters ch on ch.id = bv.chapter_id
    join public.bible_books b on b.id = ch.book_id
    where b.abbrev = 'John' and ch.number = 3;
  select (public.get_chapter('KJV','Ps',119)->>'verse_count')::int into p;

  if v <> 31102 then raise exception 'verses = %, expected 31102', v; end if;
  if c <> 1189  then raise exception 'chapters = %, expected 1189', c; end if;
  if j <> 36    then raise exception 'John 3 verses = %, expected 36', j; end if;
  if p <> 176   then raise exception 'Psalm 119 verse_count = %, expected 176', p; end if;
  if (select reference from public.search_bible('lean not unto','KJV',1)) <> 'Proverbs 3:5'
    then raise exception 'search("lean not unto") did not return Proverbs 3:5 first'; end if;

  raise notice 'KJV OK: % verses, % chapters, John 3 = %, Psalm 119 = %', v, c, j, p;
end $$;
SQL

echo "KJV import verified."
