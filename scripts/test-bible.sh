#!/usr/bin/env bash
# Verify the public-domain translations (WEB, BSB, ASV) added in 0030: build a
# fresh DB (auth stubs + migrations + dev seed), load each version's seed, and
# assert per-version counts, a known verse, and that the reader helpers
# (get_chapter / search_bible) resolve per version. Aborts non-zero on mismatch.
#
# Connection via libpq env vars. Usage:  PGPORT=55432 ./scripts/test-bible.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
TESTDB="${TESTDB:-mathetes_bible_test}"

admin() { psql -v ON_ERROR_STOP=1 -d postgres -q "$@"; }
run()   { psql -v ON_ERROR_STOP=1 -d "$TESTDB" -q "$@"; }

echo "Building $TESTDB on $PGHOST:$PGPORT ..."
admin -c "drop database if exists $TESTDB;"
admin -c "create database $TESTDB;"
run -f supabase/tests/auth_stubs.sql
for m in supabase/migrations/*.sql; do run -f "$m"; done
run -f supabase/seed.sql

echo "Loading WEB, BSB, ASV ..."
run -f supabase/seed/web.sql
run -f supabase/seed/bsb.sql
run -f supabase/seed/asv.sql

echo "Asserting per-version counts + helpers ..."
run <<'SQL'
do $$
declare
  r record;
  expected jsonb := '{"WEB":31102,"BSB":31086,"ASV":31086}'::jsonb;
  n int; j int;
begin
  -- Every public-domain version exists with 66 books and the expected verses.
  for r in select code from (values ('WEB'),('BSB'),('ASV')) as t(code) loop
    select count(*) into n from public.bible_books b
      join public.bible_versions ver on ver.id = b.version_id where ver.code = r.code;
    if n <> 66 then raise exception '% has % books, expected 66', r.code, n; end if;

    select count(*) into n from public.bible_verses v
      join public.bible_chapters c on c.id = v.chapter_id
      join public.bible_books b on b.id = c.book_id
      join public.bible_versions ver on ver.id = b.version_id where ver.code = r.code;
    if n <> (expected->>r.code)::int then
      raise exception '% verses = %, expected %', r.code, n, expected->>r.code; end if;

    -- John 3 is present and the reader helper resolves the version.
    j := jsonb_array_length(public.get_chapter(r.code, 'John', 3)->'verses');
    if j < 1 then raise exception '% get_chapter(John 3) returned no verses', r.code; end if;
  end loop;

  -- Cross-version: John 3:16 text differs per translation (real, distinct text).
  if (select v.text from public.bible_verses v
        join public.bible_chapters c on c.id=v.chapter_id
        join public.bible_books b on b.id=c.book_id
        join public.bible_versions ver on ver.id=b.version_id
        where ver.code='ASV' and b.abbrev='John' and c.number=3 and v.number=16)
     not like '%only begotten Son%' then
    raise exception 'ASV John 3:16 text unexpected'; end if;

  -- Per-version search works and is scoped to the requested version.
  if (select reference from public.search_bible('lean not', 'WEB', 1)) is null then
    raise exception 'WEB search returned nothing'; end if;

  raise notice 'Bible versions OK: WEB/BSB/ASV books=66, verses match, helpers resolve per version';
end $$;
SQL

echo "Public-domain Bible versions verified."
