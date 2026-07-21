-- 0038_formation_practices.sql
-- A calm, pastoral formation layer around Reading Plans. This deliberately
-- avoids public scores, rankings, and leaderboards: a student's rhythm,
-- collections, and milestones are private. House quests, events, and campus
-- missions are opt-in shared practices.

-- ---------------------------------------------------------------------------
-- Private rhythm garden: a small event log from which the mobile app derives
-- a student's recent growth visual and gentle milestones.
-- ---------------------------------------------------------------------------

create table if not exists public.formation_activities (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.user_profiles(id) on delete cascade,
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  kind        text not null check (kind in (
    'word_read', 'devotional_read', 'plan_day_complete', 'reflection_saved',
    'prayer_offered', 'verse_shared', 'quest_complete', 'mission_complete'
  )),
  target_key  text not null default '',
  occurred_on date not null default (timezone('Africa/Lagos', now())::date),
  created_at  timestamptz not null default now(),
  unique (user_id, kind, target_key, occurred_on)
);

create index if not exists idx_formation_activities_private_rhythm
  on public.formation_activities (user_id, occurred_on desc);

alter table public.formation_activities enable row level security;

drop policy if exists "formation_activities_select_own" on public.formation_activities;
create policy "formation_activities_select_own" on public.formation_activities for select
  to authenticated using (public.is_active_member() and user_id = public.current_profile_id());

-- Only the logging RPC below writes these rows. A client cannot choose another
-- member's parish or fabricate another member's activity.

create or replace function public.record_formation_activity(
  p_kind text,
  p_target_key text default ''
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid := public.current_parish_id();
begin
  if v_me is null or not public.is_active_member() then
    raise exception 'active membership required';
  end if;
  if p_kind not in (
    'word_read', 'devotional_read', 'plan_day_complete', 'reflection_saved',
    'prayer_offered', 'verse_shared', 'quest_complete', 'mission_complete'
  ) then
    raise exception 'unsupported formation activity';
  end if;

  insert into public.formation_activities (user_id, parish_id, kind, target_key)
  values (v_me, v_parish, p_kind, coalesce(left(p_target_key, 160), ''))
  on conflict (user_id, kind, target_key, occurred_on) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Private Scripture collections. Existing bookmarks remain the inbox; these
-- are optional named shelves such as "When I am anxious" or "Identity".
-- ---------------------------------------------------------------------------

create table if not exists public.scripture_collections (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.user_profiles(id) on delete cascade,
  title       text not null check (char_length(trim(title)) between 1 and 80),
  color       text not null default 'blue' check (color in ('blue', 'sage', 'rose', 'amber', 'violet')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.scripture_collection_verses (
  collection_id uuid not null references public.scripture_collections(id) on delete cascade,
  verse_id      uuid not null references public.bible_verses(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (collection_id, verse_id)
);

create index if not exists idx_scripture_collections_user
  on public.scripture_collections (user_id, created_at desc);

create or replace function public.owns_scripture_collection(p_collection uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.scripture_collections c
    where c.id = p_collection and c.user_id = public.current_profile_id()
  );
$$;

alter table public.scripture_collections enable row level security;
alter table public.scripture_collection_verses enable row level security;

drop policy if exists "scripture_collections_own" on public.scripture_collections;
create policy "scripture_collections_own" on public.scripture_collections for all
  to authenticated
  using (public.is_active_member() and user_id = public.current_profile_id())
  with check (public.is_active_member() and user_id = public.current_profile_id());

drop policy if exists "scripture_collection_verses_own" on public.scripture_collection_verses;
create policy "scripture_collection_verses_own" on public.scripture_collection_verses for all
  to authenticated
  using (public.is_active_member() and public.owns_scripture_collection(collection_id))
  with check (public.is_active_member() and public.owns_scripture_collection(collection_id));

drop trigger if exists trg_scripture_collections_updated_at on public.scripture_collections;
create trigger trg_scripture_collections_updated_at
  before update on public.scripture_collections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Shared practices. One scoped campaign model powers both House Quests and
-- Campus Missions. Members see only published campaigns in their parish and
-- own house/campus scope, then record a private completion. There is no list
-- of who has or has not completed a practice.
-- ---------------------------------------------------------------------------

create table if not exists public.formation_campaigns (
  id              uuid primary key default gen_random_uuid(),
  parish_id       uuid not null references public.parishes(id) on delete cascade,
  kind            text not null check (kind in ('house_quest', 'campus_mission')),
  title           text not null check (char_length(trim(title)) between 1 and 160),
  body            text not null default '',
  scripture_ref   text,
  cover_image_url text,
  house_id        uuid references public.houses(id) on delete cascade,
  campus_id       uuid references public.campuses(id) on delete cascade,
  starts_on       date not null,
  ends_on         date not null,
  published       boolean not null default false,
  published_at    timestamptz,
  author_id       uuid references public.user_profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_on >= starts_on),
  check (
    (kind = 'house_quest' and house_id is not null and campus_id is null)
    or (kind = 'campus_mission' and campus_id is not null and house_id is null)
  )
);

create table if not exists public.formation_campaign_completions (
  campaign_id  uuid not null references public.formation_campaigns(id) on delete cascade,
  user_id      uuid not null references public.user_profiles(id) on delete cascade,
  completed_at timestamptz not null default now(),
  note         text,
  primary key (campaign_id, user_id)
);

create index if not exists idx_formation_campaigns_member_feed
  on public.formation_campaigns (parish_id, published, starts_on desc, ends_on desc);

create or replace function public.validate_formation_campaign_scope()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_scope_parish uuid;
begin
  if new.house_id is not null then
    select parish_id into v_scope_parish from public.houses where id = new.house_id;
  else
    select parish_id into v_scope_parish from public.campuses where id = new.campus_id;
  end if;
  if v_scope_parish is null or v_scope_parish <> new.parish_id then
    raise exception 'campaign scope must belong to the campaign parish';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_formation_campaign_scope on public.formation_campaigns;
create trigger trg_validate_formation_campaign_scope
  before insert or update on public.formation_campaigns
  for each row execute function public.validate_formation_campaign_scope();

create or replace function public.can_read_formation_campaign(p_campaign uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.formation_campaigns c
    join public.user_profiles me on me.id = public.current_profile_id()
    where c.id = p_campaign
      and c.parish_id = public.current_parish_id()
      and public.is_active_member()
      and (
        public.is_parish_admin()
        or (c.published and (
          (c.house_id is not null and c.house_id = me.house_id)
          or (c.campus_id is not null and c.campus_id = me.campus_id)
        ))
      )
  );
$$;

alter table public.formation_campaigns enable row level security;
alter table public.formation_campaign_completions enable row level security;

drop policy if exists "formation_campaigns_select_scoped" on public.formation_campaigns;
create policy "formation_campaigns_select_scoped" on public.formation_campaigns for select
  to authenticated
  using (public.can_read_formation_campaign(id));

drop policy if exists "formation_campaigns_admin_write" on public.formation_campaigns;
create policy "formation_campaigns_admin_write" on public.formation_campaigns for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

drop policy if exists "formation_campaign_completions_own" on public.formation_campaign_completions;
create policy "formation_campaign_completions_own" on public.formation_campaign_completions for all
  to authenticated
  using (user_id = public.current_profile_id() and public.can_read_formation_campaign(campaign_id))
  with check (user_id = public.current_profile_id() and public.can_read_formation_campaign(campaign_id));

drop trigger if exists trg_formation_campaigns_updated_at on public.formation_campaigns;
create trigger trg_formation_campaigns_updated_at
  before update on public.formation_campaigns
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Fellowship Cards: parish/house/campus events with private RSVP choices.
-- ---------------------------------------------------------------------------

create table if not exists public.fellowship_events (
  id              uuid primary key default gen_random_uuid(),
  parish_id       uuid not null references public.parishes(id) on delete cascade,
  title           text not null check (char_length(trim(title)) between 1 and 160),
  description     text not null default '',
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  location        text,
  cover_image_url text,
  house_id        uuid references public.houses(id) on delete cascade,
  campus_id       uuid references public.campuses(id) on delete cascade,
  published       boolean not null default false,
  published_at    timestamptz,
  author_id       uuid references public.user_profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at),
  check (not (house_id is not null and campus_id is not null))
);

create table if not exists public.fellowship_event_rsvps (
  event_id      uuid not null references public.fellowship_events(id) on delete cascade,
  user_id       uuid not null references public.user_profiles(id) on delete cascade,
  response      text not null check (response in ('going', 'interested', 'not_going')),
  updated_at    timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists idx_fellowship_events_member_feed
  on public.fellowship_events (parish_id, published, starts_at);

create or replace function public.validate_fellowship_event_scope()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_scope_parish uuid;
begin
  if new.house_id is not null then
    select parish_id into v_scope_parish from public.houses where id = new.house_id;
  elsif new.campus_id is not null then
    select parish_id into v_scope_parish from public.campuses where id = new.campus_id;
  else
    return new;
  end if;
  if v_scope_parish is null or v_scope_parish <> new.parish_id then
    raise exception 'event scope must belong to the event parish';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_fellowship_event_scope on public.fellowship_events;
create trigger trg_validate_fellowship_event_scope
  before insert or update on public.fellowship_events
  for each row execute function public.validate_fellowship_event_scope();

create or replace function public.can_read_fellowship_event(p_event uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.fellowship_events e
    join public.user_profiles me on me.id = public.current_profile_id()
    where e.id = p_event
      and e.parish_id = public.current_parish_id()
      and public.is_active_member()
      and (
        public.is_parish_admin()
        or (e.published and (
          e.house_id is null and e.campus_id is null
          or e.house_id = me.house_id
          or e.campus_id = me.campus_id
        ))
      )
  );
$$;

alter table public.fellowship_events enable row level security;
alter table public.fellowship_event_rsvps enable row level security;

drop policy if exists "fellowship_events_select_scoped" on public.fellowship_events;
create policy "fellowship_events_select_scoped" on public.fellowship_events for select
  to authenticated using (public.can_read_fellowship_event(id));

drop policy if exists "fellowship_events_admin_write" on public.fellowship_events;
create policy "fellowship_events_admin_write" on public.fellowship_events for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

drop policy if exists "fellowship_event_rsvps_own" on public.fellowship_event_rsvps;
create policy "fellowship_event_rsvps_own" on public.fellowship_event_rsvps for all
  to authenticated
  using (user_id = public.current_profile_id() and public.can_read_fellowship_event(event_id))
  with check (user_id = public.current_profile_id() and public.can_read_fellowship_event(event_id));

drop trigger if exists trg_fellowship_events_updated_at on public.fellowship_events;
create trigger trg_fellowship_events_updated_at
  before update on public.fellowship_events
  for each row execute function public.set_updated_at();

-- Answered Prayers remain private to the author, except for the existing
-- house/parish visibility of the request itself. Only the author may mark and
-- describe an answer; leaders do not receive a private-answer write path.
alter table public.prayer_requests
  add column if not exists answered_at timestamptz,
  add column if not exists answer_note text;

create or replace function public.mark_prayer_answered(
  p_request uuid,
  p_answer_note text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
begin
  if v_me is null or not public.is_active_member() then raise exception 'active membership required'; end if;
  update public.prayer_requests
    set answered_at = now(), answer_note = nullif(trim(p_answer_note), '')
    where id = p_request and author_id = v_me;
  if not found then raise exception 'prayer request not found'; end if;
end;
$$;
