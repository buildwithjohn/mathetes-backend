-- 0005_engagement.sql
-- Engagement: daily streaks (with one grace day per month) and a generic
-- engagement event log used for analytics.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.streaks (
  user_id                 uuid primary key references public.user_profiles(id) on delete cascade,
  current_count           int not null default 0,
  longest                 int not null default 0,
  last_check_in           date,
  grace_used_this_month   int not null default 0,
  updated_at              timestamptz not null default now()
);

create table if not exists public.engagement_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.user_profiles(id) on delete cascade,
  event_type  text not null,            -- 'check_in', 'devotional_read', 'verse_image_generated', ...
  target_id   uuid,
  created_at  timestamptz not null default now()
);

create index if not exists idx_engagement_user_type on public.engagement_events (user_id, event_type, created_at desc);
create index if not exists idx_engagement_created on public.engagement_events (created_at desc);

drop trigger if exists trg_streaks_updated_at on public.streaks;
create trigger trg_streaks_updated_at
  before update on public.streaks
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- record_check_in(): idempotent daily check-in with grace-day logic.
-- One grace day per calendar month bridges a single missed day without
-- breaking the streak. Returns the updated streak row. SECURITY DEFINER so it
-- can upsert the caller's own streak regardless of insert policy nuances.
-- ---------------------------------------------------------------------------

create or replace function public.record_check_in()
returns public.streaks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := public.current_profile_id();
  s        public.streaks;
  v_today  date := current_date;
  v_gap    int;
  v_grace  int;
begin
  if v_uid is null then
    raise exception 'no authenticated profile';
  end if;

  insert into public.streaks (user_id) values (v_uid)
  on conflict (user_id) do nothing;

  select * into s from public.streaks where user_id = v_uid for update;

  -- Reset the monthly grace allowance when we roll into a new month.
  v_grace := s.grace_used_this_month;
  if s.last_check_in is null or date_trunc('month', s.last_check_in) <> date_trunc('month', v_today) then
    v_grace := 0;
  end if;

  if s.last_check_in = v_today then
    -- Already checked in today: no change.
    return s;
  end if;

  if s.last_check_in is null then
    s.current_count := 1;
  else
    v_gap := v_today - s.last_check_in;
    if v_gap = 1 then
      s.current_count := s.current_count + 1;
    elsif v_gap = 2 and v_grace < 1 then
      -- Spend the monthly grace day to keep the streak alive.
      s.current_count := s.current_count + 1;
      v_grace := v_grace + 1;
    else
      s.current_count := 1;
    end if;
  end if;

  s.longest := greatest(s.longest, s.current_count);
  s.last_check_in := v_today;
  s.grace_used_this_month := v_grace;

  update public.streaks
    set current_count = s.current_count,
        longest = s.longest,
        last_check_in = s.last_check_in,
        grace_used_this_month = s.grace_used_this_month
    where user_id = v_uid;

  insert into public.engagement_events (user_id, event_type) values (v_uid, 'check_in');

  select * into s from public.streaks where user_id = v_uid;
  return s;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.streaks            enable row level security;
alter table public.engagement_events  enable row level security;

-- Streaks: owner reads/writes their own row.
create policy "streaks_own" on public.streaks for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Engagement events: owner reads/inserts their own; parish admins may read
-- events for members of their parish (analytics).
create policy "engagement_select_own" on public.engagement_events for select
  to authenticated
  using (user_id = public.current_profile_id());

create policy "engagement_insert_own" on public.engagement_events for insert
  to authenticated
  with check (user_id = public.current_profile_id());

create policy "engagement_select_admin" on public.engagement_events for select
  to authenticated
  using (
    public.is_parish_admin()
    and exists (
      select 1 from public.user_profiles p
      where p.id = engagement_events.user_id
        and p.parish_id = public.current_parish_id()
    )
  );
