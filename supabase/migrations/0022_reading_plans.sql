-- 0022_reading_plans.sql
-- V2.0 — Reading plans (guided multi-day scripture + reflection journeys).
--
-- PASTORAL GUARDRAILS (non-negotiable; encoded below in RLS + RPCs):
--   * Reflections are PRIVATE by default.
--   * A user may opt, per day, to share a reflection with their DISCIPLER only
--     (never the house leader, never the pastor/admin).
--   * No public completion data and no leaderboards. There is no policy path by
--     which one member can read another's progress except the discipler-share
--     above; admins can see that a subscription exists (for support/analytics)
--     but NOT the reflection responses.
--   * Plans and plan days are authored by parish admins only.
--   * Pausing and resuming is normal — pastoral grace, not legalism. Pausing is
--     a first-class state, not a failure.
--   * Per-plan streaks are OPT-IN and disabled by default.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.reading_plans (
  id              uuid primary key default gen_random_uuid(),
  parish_id       uuid not null references public.parishes(id) on delete cascade,
  slug            text not null,
  title           text not null,
  description     text not null,
  cover_image_url text,
  length_days     integer not null check (length_days > 0 and length_days <= 365),
  difficulty      text check (difficulty in ('starter', 'intermediate', 'deep')),
  author_id       uuid references public.user_profiles(id),
  sequence_locked boolean not null default true,
  published       boolean not null default false,
  published_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (parish_id, slug)
);

create table if not exists public.reading_plan_days (
  id                  uuid primary key default gen_random_uuid(),
  plan_id             uuid not null references public.reading_plans(id) on delete cascade,
  day_number          integer not null check (day_number > 0),
  title               text not null,
  scripture_reference text not null,
  scripture_text      text,
  reflection_body     text not null,
  reflection_prompt   text not null,
  audio_url           text,
  devotional_id       uuid references public.devotionals(id) on delete set null,
  created_at          timestamptz not null default now(),
  unique (plan_id, day_number)
);

create table if not exists public.reading_plan_subscriptions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.user_profiles(id) on delete cascade,
  plan_id          uuid not null references public.reading_plans(id) on delete cascade,
  started_at       timestamptz not null default now(),
  current_day      integer not null default 1,
  last_activity_at timestamptz not null default now(),
  completed_at     timestamptz,
  paused           boolean not null default false,
  streak_enabled   boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (user_id, plan_id)
);

create table if not exists public.reading_plan_progress (
  id                   uuid primary key default gen_random_uuid(),
  subscription_id      uuid not null references public.reading_plan_subscriptions(id) on delete cascade,
  day_id               uuid not null references public.reading_plan_days(id) on delete cascade,
  completed_at         timestamptz not null default now(),
  reflection_response  text,
  share_with_discipler boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (subscription_id, day_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists idx_reading_plans_parish_pub
  on public.reading_plans (parish_id, published, published_at desc);
create index if not exists idx_reading_plan_days_plan
  on public.reading_plan_days (plan_id, day_number);
create index if not exists idx_reading_plan_subs_user
  on public.reading_plan_subscriptions (user_id, paused, completed_at);
create index if not exists idx_reading_plan_progress_sub
  on public.reading_plan_progress (subscription_id, day_id);

-- Keep reading_plans.updated_at fresh (set_updated_at from 0002).
drop trigger if exists trg_reading_plans_updated_at on public.reading_plans;
create trigger trg_reading_plans_updated_at
  before update on public.reading_plans
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Access helpers (SECURITY DEFINER so the discipler-share check can read the
-- subscription/profile without tripping their own RLS).
-- ---------------------------------------------------------------------------

create or replace function public.owns_plan_subscription(p_sub uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.reading_plan_subscriptions s
    where s.id = p_sub and s.user_id = public.current_profile_id()
  );
$$;

-- True when the caller is the DISCIPLER of the subscription's owner. Used only
-- in combination with a per-row share_with_discipler flag.
create or replace function public.is_discipler_for_subscription(p_sub uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.reading_plan_subscriptions s
    join public.user_profiles owner on owner.id = s.user_id
    where s.id = p_sub
      and owner.discipler_id is not null
      and owner.discipler_id = public.current_profile_id()
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.reading_plans              enable row level security;
alter table public.reading_plan_days          enable row level security;
alter table public.reading_plan_subscriptions enable row level security;
alter table public.reading_plan_progress      enable row level security;

-- reading_plans: members read published plans in their parish; admins manage.
create policy "reading_plans_select_published" on public.reading_plans for select
  to authenticated
  using (published = true and parish_id = public.current_parish_id());

create policy "reading_plans_admin_write" on public.reading_plans for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- reading_plan_days: visible when the parent plan is in the caller's parish and
-- either published (members) or the caller is an admin. Admins manage.
create policy "reading_plan_days_select" on public.reading_plan_days for select
  to authenticated
  using (
    exists (
      select 1 from public.reading_plans p
      where p.id = reading_plan_days.plan_id
        and p.parish_id = public.current_parish_id()
        and (p.published or public.is_parish_admin())
    )
  );

create policy "reading_plan_days_admin_write" on public.reading_plan_days for all
  to authenticated
  using (
    public.is_parish_admin()
    and exists (select 1 from public.reading_plans p
                where p.id = reading_plan_days.plan_id and p.parish_id = public.current_parish_id())
  )
  with check (
    public.is_parish_admin()
    and exists (select 1 from public.reading_plans p
                where p.id = reading_plan_days.plan_id and p.parish_id = public.current_parish_id())
  );

-- reading_plan_subscriptions: owner manages their own; admins may read (support
-- / analytics) but the progress + reflections below remain closed to them.
create policy "reading_plan_subs_owner" on public.reading_plan_subscriptions for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

create policy "reading_plan_subs_admin_select" on public.reading_plan_subscriptions for select
  to authenticated
  using (
    public.is_parish_admin()
    and exists (select 1 from public.reading_plans p
                where p.id = reading_plan_subscriptions.plan_id and p.parish_id = public.current_parish_id())
  );

-- reading_plan_progress: owner reads/writes their own; the owner's discipler may
-- read ONLY the rows the owner explicitly shared. No admin/pastor/house-leader path.
create policy "reading_plan_progress_owner" on public.reading_plan_progress for all
  to authenticated
  using (public.owns_plan_subscription(subscription_id))
  with check (public.owns_plan_subscription(subscription_id));

create policy "reading_plan_progress_discipler_select" on public.reading_plan_progress for select
  to authenticated
  using (share_with_discipler = true and public.is_discipler_for_subscription(subscription_id));

-- ---------------------------------------------------------------------------
-- RPCs (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- Subscribe the caller to a plan. Idempotent. Refuses unpublished / out-of-parish.
create or replace function public.subscribe_to_plan(p_plan_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me     uuid := public.current_profile_id();
  v_pub    boolean;
  v_parish uuid;
  v_sub    uuid;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;

  select published, parish_id into v_pub, v_parish from public.reading_plans where id = p_plan_id;
  if v_parish is null then raise exception 'reading plan not found'; end if;
  if v_parish <> public.current_parish_id() then raise exception 'reading plan is not in your parish'; end if;
  if not v_pub then raise exception 'reading plan is not published'; end if;

  select id into v_sub from public.reading_plan_subscriptions where user_id = v_me and plan_id = p_plan_id;
  if v_sub is not null then
    return v_sub;  -- idempotent
  end if;

  insert into public.reading_plan_subscriptions (user_id, plan_id)
    values (v_me, p_plan_id)
    returning id into v_sub;
  return v_sub;
end;
$$;

-- Complete (or re-save) a day for the caller's subscription. Advances the
-- subscription and marks completion on the final day.
create or replace function public.complete_plan_day(
  p_day_id uuid,
  p_reflection_response text default null,
  p_share_with_discipler boolean default false
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me     uuid := public.current_profile_id();
  v_plan   uuid;
  v_daynum integer;
  v_len    integer;
  v_sub    uuid;
  v_prog   uuid;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;

  select plan_id, day_number into v_plan, v_daynum from public.reading_plan_days where id = p_day_id;
  if v_plan is null then raise exception 'reading plan day not found'; end if;

  select id into v_sub from public.reading_plan_subscriptions where user_id = v_me and plan_id = v_plan;
  if v_sub is null then raise exception 'no active subscription for this plan'; end if;

  insert into public.reading_plan_progress (subscription_id, day_id, reflection_response, share_with_discipler)
    values (v_sub, p_day_id, p_reflection_response, p_share_with_discipler)
  on conflict (subscription_id, day_id) do update
    set reflection_response = excluded.reflection_response,
        share_with_discipler = excluded.share_with_discipler,
        completed_at = now()
  returning id into v_prog;

  select length_days into v_len from public.reading_plans where id = v_plan;

  update public.reading_plan_subscriptions
    set current_day = greatest(current_day, least(v_daynum + 1, v_len + 1)),
        last_activity_at = now(),
        completed_at = case when v_daynum >= v_len then now() else completed_at end
    where id = v_sub;

  return v_prog;
end;
$$;

-- Toggle pause on the caller's own subscription. Returns the new paused state.
create or replace function public.toggle_plan_pause(p_subscription_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := public.current_profile_id();
  v_owner uuid;
  v_new   boolean;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  select user_id into v_owner from public.reading_plan_subscriptions where id = p_subscription_id;
  if v_owner is null then raise exception 'subscription not found'; end if;
  if v_owner <> v_me then raise exception 'not your subscription'; end if;

  update public.reading_plan_subscriptions
    set paused = not paused, last_activity_at = now()
    where id = p_subscription_id
    returning paused into v_new;
  return v_new;
end;
$$;
