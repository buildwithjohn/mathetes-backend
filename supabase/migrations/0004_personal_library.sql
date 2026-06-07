-- 0004_personal_library.sql
-- Personal library: bookmarks, highlights, notes, reading position.
-- Strictly per-user data. Every row is owned by exactly one profile and only
-- that profile can read or write it.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  verse_id   uuid references public.bible_verses(id) on delete set null,
  body       text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.bookmarks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  verse_id   uuid not null references public.bible_verses(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, verse_id)
);

create table if not exists public.highlights (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  verse_id   uuid not null references public.bible_verses(id) on delete cascade,
  color      text not null default 'copper'
               check (color in ('copper', 'gold', 'sage', 'oxblood', 'blue')),
  note_id    uuid references public.notes(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, verse_id)
);

create table if not exists public.reading_position (
  user_id        uuid primary key references public.user_profiles(id) on delete cascade,
  version_id     uuid references public.bible_versions(id) on delete set null,
  book_id        uuid references public.bible_books(id) on delete set null,
  chapter_number int,
  verse_number   int,
  updated_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists idx_notes_user      on public.notes (user_id, updated_at desc);
create index if not exists idx_notes_verse     on public.notes (verse_id);
create index if not exists idx_bookmarks_user  on public.bookmarks (user_id, created_at desc);
create index if not exists idx_highlights_user on public.highlights (user_id, created_at desc);

-- Keep updated_at fresh (reuses set_updated_at from 0002).
drop trigger if exists trg_notes_updated_at on public.notes;
create trigger trg_notes_updated_at
  before update on public.notes
  for each row execute function public.set_updated_at();

drop trigger if exists trg_reading_position_updated_at on public.reading_position;
create trigger trg_reading_position_updated_at
  before update on public.reading_position
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: each table is private to its owner.
-- ---------------------------------------------------------------------------

alter table public.notes             enable row level security;
alter table public.bookmarks         enable row level security;
alter table public.highlights        enable row level security;
alter table public.reading_position  enable row level security;

create policy "notes_own" on public.notes for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

create policy "bookmarks_own" on public.bookmarks for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

create policy "highlights_own" on public.highlights for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

create policy "reading_position_own" on public.reading_position for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());
