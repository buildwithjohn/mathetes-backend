-- 0049_saved_daily_content.sql
-- Private library support for the daily Word and devotional reflection.

create table if not exists public.word_bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  word_of_day_id uuid not null references public.word_of_day(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, word_of_day_id)
);

create index if not exists idx_word_bookmarks_user_created
  on public.word_bookmarks (user_id, created_at desc);

alter table public.word_bookmarks enable row level security;

drop policy if exists "word_bookmarks_own" on public.word_bookmarks;
create policy "word_bookmarks_own" on public.word_bookmarks for all to authenticated
  using (user_id = public.current_profile_id())
  with check (
    user_id = public.current_profile_id()
    and exists (
      select 1 from public.word_of_day w
      where w.id = word_of_day_id
        and w.parish_id = public.current_parish_id()
        and w.status in ('published', 'scheduled')
        and w.publish_date <= timezone('Africa/Lagos', now())::date
    )
  );

create table if not exists public.devotional_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  devotional_id uuid not null references public.devotionals(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, devotional_id)
);

create index if not exists idx_devotional_notes_user_updated
  on public.devotional_notes (user_id, updated_at desc);

alter table public.devotional_notes enable row level security;

drop policy if exists "devotional_notes_own" on public.devotional_notes;
create policy "devotional_notes_own" on public.devotional_notes for all to authenticated
  using (user_id = public.current_profile_id())
  with check (
    user_id = public.current_profile_id()
    and exists (
      select 1 from public.devotionals d
      where d.id = devotional_id
        and d.parish_id = public.current_parish_id()
        and d.status in ('published', 'scheduled')
        and (d.publish_date is null or d.publish_date <= timezone('Africa/Lagos', now())::date)
    )
  );

drop trigger if exists trg_devotional_notes_updated_at on public.devotional_notes;
create trigger trg_devotional_notes_updated_at before update on public.devotional_notes
  for each row execute function public.set_updated_at();
