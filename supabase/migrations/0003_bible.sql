-- 0003_bible.sql
-- Bible reader: versions, books, chapters, verses with full-text search.
-- MVP ships KJV only (public domain). Readable by every authenticated user;
-- no write access except the service role (seed/import runs as owner).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.bible_versions (
  id        uuid primary key default gen_random_uuid(),
  code      text unique not null,            -- e.g. 'KJV'
  name      text not null,                   -- 'King James Version'
  language  text not null default 'en',
  license   text,                            -- 'Public Domain'
  version   text,                            -- source revision, optional
  created_at timestamptz not null default now()
);

create table if not exists public.bible_books (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references public.bible_versions(id) on delete cascade,
  name        text not null,                 -- 'John'
  abbrev      text not null,                 -- 'John' / 'Prov' / '1John'
  testament   text not null check (testament in ('OT', 'NT')),
  book_order  int not null,                  -- 1..66
  unique (version_id, book_order),
  unique (version_id, abbrev)
);

create table if not exists public.bible_chapters (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null references public.bible_books(id) on delete cascade,
  number      int not null,
  verse_count int not null default 0,
  unique (book_id, number)
);

create table if not exists public.bible_verses (
  id             uuid primary key default gen_random_uuid(),
  chapter_id     uuid not null references public.bible_chapters(id) on delete cascade,
  number         int not null,
  text           text not null,
  search_vector  tsvector,
  unique (chapter_id, number)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists idx_bible_books_version on public.bible_books (version_id, book_order);
create index if not exists idx_bible_chapters_book on public.bible_chapters (book_id, number);
create index if not exists idx_bible_verses_chapter on public.bible_verses (chapter_id, number);
create index if not exists idx_bible_verses_search on public.bible_verses using gin (search_vector);

-- ---------------------------------------------------------------------------
-- search_vector maintenance
-- ---------------------------------------------------------------------------

create or replace function public.bible_verses_search_vector()
returns trigger
language plpgsql
as $$
begin
  new.search_vector := to_tsvector('english', coalesce(new.text, ''));
  return new;
end;
$$;

drop trigger if exists trg_bible_verses_search on public.bible_verses;
create trigger trg_bible_verses_search
  before insert or update of text on public.bible_verses
  for each row execute function public.bible_verses_search_vector();

-- Keep chapters.verse_count in sync as verses are imported.
create or replace function public.bible_sync_verse_count()
returns trigger
language plpgsql
as $$
declare
  v_chapter uuid := coalesce(new.chapter_id, old.chapter_id);
begin
  update public.bible_chapters c
    set verse_count = (select count(*) from public.bible_verses v where v.chapter_id = c.id)
    where c.id = v_chapter;
  return null;
end;
$$;

drop trigger if exists trg_bible_verse_count on public.bible_verses;
create trigger trg_bible_verse_count
  after insert or delete on public.bible_verses
  for each row execute function public.bible_sync_verse_count();

-- ---------------------------------------------------------------------------
-- Reference parsing & lookup helpers
-- ---------------------------------------------------------------------------

-- parse_reference('John 3:16') -> book_id, chapter, verse (verse may be null).
-- Handles numbered books ('1 John 1:9', '2 Cor 5:17') and chapter-only refs.
create or replace function public.parse_reference(ref text, version_code text default 'KJV')
returns table (book_id uuid, book_name text, chapter int, verse int)
language plpgsql
stable
as $$
declare
  m text[];
  v_book text;
  v_chapter int;
  v_verse int;
begin
  ref := btrim(ref);

  -- "Book C:V"
  m := regexp_match(ref, '^(.+?)\s+(\d+):(\d+)$');
  if m is null then
    -- "Book C"
    m := regexp_match(ref, '^(.+?)\s+(\d+)$');
    if m is null then
      return;
    end if;
    v_book := m[1]; v_chapter := m[2]::int; v_verse := null;
  else
    v_book := m[1]; v_chapter := m[2]::int; v_verse := m[3]::int;
  end if;

  return query
    select b.id, b.name, v_chapter, v_verse
    from public.bible_books b
    join public.bible_versions ver on ver.id = b.version_id
    where ver.code = version_code
      and (lower(b.name) = lower(v_book) or lower(b.abbrev) = lower(replace(v_book, ' ', '')))
    limit 1;
end;
$$;

-- get_chapter('KJV', 'John', 3) -> { reference, verses: [{number, text}, ...] }
create or replace function public.get_chapter(version_code text, book_abbrev text, chapter_number int)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'version', ver.code,
    'book', b.name,
    'abbrev', b.abbrev,
    'chapter', c.number,
    'reference', b.name || ' ' || c.number,
    'verse_count', c.verse_count,
    'verses', coalesce(
      (select jsonb_agg(jsonb_build_object('number', v.number, 'text', v.text) order by v.number)
       from public.bible_verses v where v.chapter_id = c.id),
      '[]'::jsonb)
  )
  from public.bible_chapters c
  join public.bible_books b on b.id = c.book_id
  join public.bible_versions ver on ver.id = b.version_id
  where ver.code = version_code
    and (lower(b.abbrev) = lower(book_abbrev) or lower(b.name) = lower(book_abbrev))
    and c.number = chapter_number
  limit 1;
$$;

-- search_bible('lean not unto', 'KJV') -> ranked verses (websearch grammar).
create or replace function public.search_bible(query text, version_code text default 'KJV', max_results int default 50)
returns table (
  verse_id  uuid,
  reference text,
  book_name text,
  chapter   int,
  verse     int,
  text      text,
  rank      real
)
language sql
stable
as $$
  select
    v.id,
    b.name || ' ' || c.number || ':' || v.number as reference,
    b.name,
    c.number,
    v.number,
    v.text,
    ts_rank(v.search_vector, websearch_to_tsquery('english', query)) as rank
  from public.bible_verses v
  join public.bible_chapters c on c.id = v.chapter_id
  join public.bible_books b on b.id = c.book_id
  join public.bible_versions ver on ver.id = b.version_id
  where ver.code = version_code
    and v.search_vector @@ websearch_to_tsquery('english', query)
  order by rank desc, b.book_order, c.number, v.number
  limit greatest(max_results, 1);
$$;

-- ---------------------------------------------------------------------------
-- RLS: Bible is readable by all authenticated users. No write policy => only
-- the service role / owner (seed + import jobs) can mutate.
-- ---------------------------------------------------------------------------

alter table public.bible_versions enable row level security;
alter table public.bible_books    enable row level security;
alter table public.bible_chapters enable row level security;
alter table public.bible_verses   enable row level security;

create policy "bible_versions_read" on public.bible_versions for select to authenticated using (true);
create policy "bible_books_read"    on public.bible_books    for select to authenticated using (true);
create policy "bible_chapters_read" on public.bible_chapters for select to authenticated using (true);
create policy "bible_verses_read"   on public.bible_verses   for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Reference data: the KJV version + all 66 books (order, testament, abbrev).
-- Idempotent. Chapters and verse text are loaded by the seed / import job
-- (see supabase/seed.sql and the full KJV import noted in the README).
-- ---------------------------------------------------------------------------

insert into public.bible_versions (id, code, name, language, license, version)
values ('00000000-0000-0000-0000-0000000b1b1e', 'KJV', 'King James Version', 'en', 'Public Domain', '1769')
on conflict (code) do nothing;

insert into public.bible_books (version_id, name, abbrev, testament, book_order)
select '00000000-0000-0000-0000-0000000b1b1e', d.name, d.abbrev, d.testament, d.ord
from (values
  ('Genesis','Gen','OT',1),('Exodus','Exod','OT',2),('Leviticus','Lev','OT',3),
  ('Numbers','Num','OT',4),('Deuteronomy','Deut','OT',5),('Joshua','Josh','OT',6),
  ('Judges','Judg','OT',7),('Ruth','Ruth','OT',8),('1 Samuel','1Sam','OT',9),
  ('2 Samuel','2Sam','OT',10),('1 Kings','1Kgs','OT',11),('2 Kings','2Kgs','OT',12),
  ('1 Chronicles','1Chr','OT',13),('2 Chronicles','2Chr','OT',14),('Ezra','Ezra','OT',15),
  ('Nehemiah','Neh','OT',16),('Esther','Esth','OT',17),('Job','Job','OT',18),
  ('Psalms','Ps','OT',19),('Proverbs','Prov','OT',20),('Ecclesiastes','Eccl','OT',21),
  ('Song of Solomon','Song','OT',22),('Isaiah','Isa','OT',23),('Jeremiah','Jer','OT',24),
  ('Lamentations','Lam','OT',25),('Ezekiel','Ezek','OT',26),('Daniel','Dan','OT',27),
  ('Hosea','Hos','OT',28),('Joel','Joel','OT',29),('Amos','Amos','OT',30),
  ('Obadiah','Obad','OT',31),('Jonah','Jonah','OT',32),('Micah','Mic','OT',33),
  ('Nahum','Nah','OT',34),('Habakkuk','Hab','OT',35),('Zephaniah','Zeph','OT',36),
  ('Haggai','Hag','OT',37),('Zechariah','Zech','OT',38),('Malachi','Mal','OT',39),
  ('Matthew','Matt','NT',40),('Mark','Mark','NT',41),('Luke','Luke','NT',42),
  ('John','John','NT',43),('Acts','Acts','NT',44),('Romans','Rom','NT',45),
  ('1 Corinthians','1Cor','NT',46),('2 Corinthians','2Cor','NT',47),('Galatians','Gal','NT',48),
  ('Ephesians','Eph','NT',49),('Philippians','Phil','NT',50),('Colossians','Col','NT',51),
  ('1 Thessalonians','1Thess','NT',52),('2 Thessalonians','2Thess','NT',53),('1 Timothy','1Tim','NT',54),
  ('2 Timothy','2Tim','NT',55),('Titus','Titus','NT',56),('Philemon','Phlm','NT',57),
  ('Hebrews','Heb','NT',58),('James','Jas','NT',59),('1 Peter','1Pet','NT',60),
  ('2 Peter','2Pet','NT',61),('1 John','1John','NT',62),('2 John','2John','NT',63),
  ('3 John','3John','NT',64),('Jude','Jude','NT',65),('Revelation','Rev','NT',66)
) as d(name, abbrev, testament, ord)
on conflict (version_id, book_order) do nothing;
