-- 0002_content.sql
-- Content: devotionals, Word of the Day, series, and uploaded assets.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.devotional_series (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  title       text not null,
  description text,
  total_days  int,
  created_by  uuid references public.user_profiles(id),
  created_at  timestamptz not null default now()
);

create table if not exists public.devotionals (
  id                    uuid primary key default gen_random_uuid(),
  parish_id             uuid not null references public.parishes(id) on delete cascade,
  series_id             uuid references public.devotional_series(id) on delete set null,
  day_in_series         int,
  title                 text not null,
  body_md               text not null default '',
  scripture_refs        text[] not null default '{}',
  reading_time_minutes  int,
  audio_url             text,
  author_id             uuid references public.user_profiles(id),
  publish_date          date,
  status                text not null default 'draft'
                          check (status in ('draft', 'scheduled', 'published')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.word_of_day (
  id            uuid primary key default gen_random_uuid(),
  parish_id     uuid not null references public.parishes(id) on delete cascade,
  verse_ref     text not null,
  verse_text    text not null,
  reflection_md text,
  prompt        text,
  author_id     uuid references public.user_profiles(id),
  publish_date  date,
  status        text not null default 'draft'
                  check (status in ('draft', 'scheduled', 'published')),
  created_at    timestamptz not null default now()
);

create table if not exists public.content_assets (
  id              uuid primary key default gen_random_uuid(),
  devotional_id   uuid references public.devotionals(id) on delete cascade,
  word_of_day_id  uuid references public.word_of_day(id) on delete cascade,
  url             text not null,
  kind            text not null check (kind in ('image', 'audio')),
  created_at      timestamptz not null default now(),
  check (devotional_id is not null or word_of_day_id is not null)
);

-- ---------------------------------------------------------------------------
-- Constraints & indexes
-- One published devotional / WOTD per parish per day.
-- ---------------------------------------------------------------------------

create unique index if not exists uq_devotionals_parish_date
  on public.devotionals (parish_id, publish_date)
  where publish_date is not null;

create unique index if not exists uq_word_of_day_parish_date
  on public.word_of_day (parish_id, publish_date)
  where publish_date is not null;

create index if not exists idx_devotionals_parish_status_date
  on public.devotionals (parish_id, status, publish_date);
create index if not exists idx_devotionals_series
  on public.devotionals (series_id);
create index if not exists idx_word_of_day_parish_status_date
  on public.word_of_day (parish_id, status, publish_date);

-- Keep updated_at fresh on devotionals.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_devotionals_updated_at on public.devotionals;
create trigger trg_devotionals_updated_at
  before update on public.devotionals
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.devotional_series enable row level security;
alter table public.devotionals       enable row level security;
alter table public.word_of_day        enable row level security;
alter table public.content_assets    enable row level security;

-- Read: parish members see published content dated today or earlier.
create policy "devotionals_select_published"
  on public.devotionals for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status = 'published' and publish_date <= current_date)
      or public.is_parish_admin()
    )
  );

create policy "word_of_day_select_published"
  on public.word_of_day for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status = 'published' and publish_date <= current_date)
      or public.is_parish_admin()
    )
  );

-- Series readable by parish members (admins manage).
create policy "devotional_series_select_parish"
  on public.devotional_series for select
  to authenticated
  using (parish_id = public.current_parish_id());

-- Content assets follow their parent's visibility (admins manage; members read
-- assets attached to content in their parish).
create policy "content_assets_select_parish"
  on public.content_assets for select
  to authenticated
  using (
    exists (
      select 1 from public.devotionals d
      where d.id = content_assets.devotional_id
        and d.parish_id = public.current_parish_id()
    )
    or exists (
      select 1 from public.word_of_day w
      where w.id = content_assets.word_of_day_id
        and w.parish_id = public.current_parish_id()
    )
  );

-- Writes: parish admins (pastor/admin) for their parish, all tables.
create policy "devotionals_admin_write"
  on public.devotionals for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "word_of_day_admin_write"
  on public.word_of_day for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "devotional_series_admin_write"
  on public.devotional_series for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "content_assets_admin_write"
  on public.content_assets for all
  to authenticated
  using (public.is_parish_admin())
  with check (public.is_parish_admin());

-- ---------------------------------------------------------------------------
-- Helper views: today's content per parish.
-- security_invoker so RLS of the querying user still applies.
-- ---------------------------------------------------------------------------

create or replace view public.todays_word_of_day
with (security_invoker = true) as
  select *
  from public.word_of_day
  where status = 'published'
    and publish_date = current_date;

create or replace view public.todays_devotional
with (security_invoker = true) as
  select *
  from public.devotionals
  where status = 'published'
    and publish_date = current_date;
