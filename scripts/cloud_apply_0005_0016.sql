-- cloud_apply_0005_0016.sql
-- Idempotent bundle of migrations 0005..0016 for the hosted DB.
-- Paste into the Supabase SQL Editor and Run. Safe to re-run: every
-- policy is dropped before recreate; tables/columns/functions/triggers
-- all use if-not-exists / or-replace. (Assumes 0001-0004 already live.)

-- ===================== 0005_engagement.sql =====================
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
drop policy if exists "streaks_own" on public.streaks;
create policy "streaks_own" on public.streaks for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Engagement events: owner reads/inserts their own; parish admins may read
-- events for members of their parish (analytics).
drop policy if exists "engagement_select_own" on public.engagement_events;
create policy "engagement_select_own" on public.engagement_events for select
  to authenticated
  using (user_id = public.current_profile_id());

drop policy if exists "engagement_insert_own" on public.engagement_events;
create policy "engagement_insert_own" on public.engagement_events for insert
  to authenticated
  with check (user_id = public.current_profile_id());

drop policy if exists "engagement_select_admin" on public.engagement_events;
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

-- ===================== 0006_chat.sql =====================
-- 0006_chat.sql
-- Chat: house groups, parish announcements, ask-pastor threads, discipler
-- chats, and DMs. This migration encodes the pastoral guardrails in RLS:
--
--   * house_group   : every member of the house can read + post.
--   * announcements : every parish member can read; only pastor/admin posts.
--   * dm            : the two participants read + post; the house leader of the
--                     pair has read-only OVERSIGHT visibility (no posting).
--   * discipler     : disciple + discipler read + post; the parish pastor has
--                     read-only OVERSIGHT visibility.
--   * ask_pastor_thread : explicit members only.
--
-- Oversight is read-only by design (visibility, not participation).

-- ---------------------------------------------------------------------------
-- Discipler relationship lives on the profile.
-- ---------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists discipler_id uuid references public.user_profiles(id) on delete set null;

create index if not exists idx_user_profiles_discipler on public.user_profiles (discipler_id);

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.chats (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null
                check (kind in ('house_group', 'announcements', 'ask_pastor_thread', 'discipler', 'dm')),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  house_id    uuid references public.houses(id) on delete cascade,
  created_by  uuid references public.user_profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.chat_members (
  chat_id      uuid not null references public.chats(id) on delete cascade,
  user_id      uuid not null references public.user_profiles(id) on delete cascade,
  role         text not null default 'member'
                 check (role in ('member', 'leader', 'pastor', 'discipler')),
  joined_at    timestamptz not null default now(),
  last_read_at timestamptz,
  muted        boolean not null default false,
  primary key (chat_id, user_id)
);

create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  chat_id     uuid not null references public.chats(id) on delete cascade,
  author_id   uuid references public.user_profiles(id) on delete set null,
  body        text,
  voice_url   text,
  image_url   text,
  kind        text not null default 'text'
                check (kind in ('text', 'voice', 'image', 'system', 'daily_prompt')),
  reply_to_id uuid references public.messages(id) on delete set null,
  edited_at   timestamptz,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  emoji      text not null check (emoji in ('🙏', '❤️', 'amen', '🔥', '✋')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create table if not exists public.pinned_messages (
  chat_id    uuid not null references public.chats(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by  uuid references public.user_profiles(id) on delete set null,
  pinned_at  timestamptz not null default now(),
  primary key (chat_id, message_id)
);

-- ---------------------------------------------------------------------------
-- Indexes (chat list + message history)
-- ---------------------------------------------------------------------------

create index if not exists idx_chats_parish on public.chats (parish_id, kind);
create index if not exists idx_chats_house on public.chats (house_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_author on public.messages (author_id);
create index if not exists idx_message_reactions_msg on public.message_reactions (message_id);

-- ---------------------------------------------------------------------------
-- Access helpers (SECURITY DEFINER: evaluate membership/oversight without
-- recursing through the RLS of the tables they guard).
-- ---------------------------------------------------------------------------

create or replace function public.is_chat_member(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_members m
    where m.chat_id = p_chat and m.user_id = public.current_profile_id()
  );
$$;

create or replace function public.is_chat_leader(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_members m
    where m.chat_id = p_chat
      and m.user_id = public.current_profile_id()
      and m.role in ('leader', 'pastor')
  );
$$;

-- Read access. Oversight is intentionally narrow (the pastoral guardrails):
--   * DMs are overseen by the house leader of the pair, NOT the pastor.
--   * Discipler chats are overseen by the parish pastor, NOT house leaders.
-- There is deliberately NO blanket pastor/admin read of private chats, so a
-- pastor cannot browse DM content (or even DM existence); reported messages are
-- the only path to a DM's content.
create or replace function public.can_read_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         -- participants of any chat they belong to
         public.is_chat_member(p_chat)
         -- every parish member reads the announcements channel
      or (c.kind = 'announcements' and c.parish_id = public.current_parish_id())
         -- every house member reads their house group
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
         -- pastor/admin read ask-pastor queue threads in their parish
      or (c.kind = 'ask_pastor_thread' and public.is_parish_admin()
          and c.parish_id = public.current_parish_id())
         -- DM oversight: house leader of the pair (chat carries their house)
      or (c.kind = 'dm' and c.house_id is not null
          and public.current_profile_id() = (select h.leader_id from public.houses h where h.id = c.house_id))
         -- discipler oversight: the parish pastor
      or (c.kind = 'discipler' and c.parish_id = public.current_parish_id()
          and public.current_user_role() = 'pastor')
    )
  );
$$;

-- Post access: participation only (oversight is read-only).
create or replace function public.can_post_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         (c.kind = 'announcements' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind in ('dm', 'discipler', 'ask_pastor_thread') and public.is_chat_member(p_chat))
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Membership automation
-- ---------------------------------------------------------------------------

-- Auto-join the house group chat when a profile is assigned (or moved) to a
-- house. Leaders of the house get the 'leader' role on the chat.
create or replace function public.sync_house_chat_membership()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_chat uuid;
  v_role text;
begin
  if new.house_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.house_id is not distinct from old.house_id then
    return new;
  end if;

  select id into v_chat from public.chats
    where kind = 'house_group' and house_id = new.house_id limit 1;
  if v_chat is null then
    return new;
  end if;

  select case when h.leader_id = new.id then 'leader' else 'member' end
    into v_role from public.houses h where h.id = new.house_id;

  insert into public.chat_members (chat_id, user_id, role)
    values (v_chat, new.id, coalesce(v_role, 'member'))
  on conflict (chat_id, user_id) do update set role = excluded.role;

  return new;
end;
$$;

drop trigger if exists trg_sync_house_chat on public.user_profiles;
create trigger trg_sync_house_chat
  after insert or update of house_id on public.user_profiles
  for each row execute function public.sync_house_chat_membership();

-- Create (idempotently) the discipler chat when a discipler is assigned.
create or replace function public.sync_discipler_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_chat   uuid;
  v_parish uuid;
begin
  if new.discipler_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.discipler_id is not distinct from old.discipler_id then
    return new;
  end if;

  -- Already have a discipler chat that contains both? Then we are done.
  select c.id into v_chat
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = new.id
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = new.discipler_id
  where c.kind = 'discipler'
  limit 1;
  if v_chat is not null then
    return new;
  end if;

  select parish_id into v_parish from public.user_profiles where id = new.id;

  insert into public.chats (kind, parish_id, created_by) values ('discipler', v_parish, new.discipler_id)
    returning id into v_chat;

  insert into public.chat_members (chat_id, user_id, role) values
    (v_chat, new.id, 'member'),
    (v_chat, new.discipler_id, 'discipler')
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_sync_discipler_chat on public.user_profiles;
create trigger trg_sync_discipler_chat
  after insert or update of discipler_id on public.user_profiles
  for each row execute function public.sync_discipler_chat();

-- Open (or reuse) a DM between the caller and another profile in the same
-- parish. The chat carries the shared house (if any) so the house leader gets
-- oversight visibility. Returns the chat id.
create or replace function public.create_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me     uuid := public.current_profile_id();
  v_chat   uuid;
  v_parish uuid;
  v_house  uuid;
  v_other_parish uuid;
  v_other_house  uuid;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  if p_other is null or p_other = v_me then raise exception 'invalid DM target'; end if;

  select parish_id, house_id into v_parish, v_house from public.user_profiles where id = v_me;
  select parish_id, house_id into v_other_parish, v_other_house from public.user_profiles where id = p_other;

  if v_other_parish is null or v_other_parish <> v_parish then
    raise exception 'DM target must be in your parish';
  end if;

  -- Existing DM between exactly these two?
  select c.id into v_chat
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = v_me
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = p_other
  where c.kind = 'dm'
  limit 1;
  if v_chat is not null then
    return v_chat;
  end if;

  insert into public.chats (kind, parish_id, house_id, created_by)
    values ('dm', v_parish, case when v_house = v_other_house then v_house else null end, v_me)
    returning id into v_chat;

  insert into public.chat_members (chat_id, user_id, role) values
    (v_chat, v_me, 'member'),
    (v_chat, p_other, 'member')
  on conflict do nothing;

  return v_chat;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.chats             enable row level security;
alter table public.chat_members      enable row level security;
alter table public.messages          enable row level security;
alter table public.message_reactions enable row level security;
alter table public.pinned_messages   enable row level security;

-- chats
drop policy if exists "chats_select" on public.chats;
create policy "chats_select" on public.chats for select
  to authenticated using (public.can_read_chat(id));

-- Members create DM/ask-pastor chats through SECURITY DEFINER RPCs; admins may
-- create/manage parish chats directly. These are write-only policies (no FOR
-- ALL) so admin write access never doubles as blanket SELECT on private chats.
drop policy if exists "chats_admin_insert" on public.chats;
create policy "chats_admin_insert" on public.chats for insert
  to authenticated
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

drop policy if exists "chats_admin_update" on public.chats;
create policy "chats_admin_update" on public.chats for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

drop policy if exists "chats_admin_delete" on public.chats;
create policy "chats_admin_delete" on public.chats for delete
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- chat_members
drop policy if exists "chat_members_select" on public.chat_members;
create policy "chat_members_select" on public.chat_members for select
  to authenticated using (public.can_read_chat(chat_id));

-- Update only your own membership (last_read_at, mute).
drop policy if exists "chat_members_update_own" on public.chat_members;
create policy "chat_members_update_own" on public.chat_members for update
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Self-join readable group/announcement chats; leave your own membership.
drop policy if exists "chat_members_insert_self" on public.chat_members;
create policy "chat_members_insert_self" on public.chat_members for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_chat(chat_id));

drop policy if exists "chat_members_delete_self" on public.chat_members;
create policy "chat_members_delete_self" on public.chat_members for delete
  to authenticated using (user_id = public.current_profile_id());

-- Admin membership management is write-only (no FOR ALL): admins never gain a
-- blanket SELECT over private chat memberships (e.g. who DMs whom).
drop policy if exists "chat_members_admin_insert" on public.chat_members;
create policy "chat_members_admin_insert" on public.chat_members for insert
  to authenticated
  with check (public.is_parish_admin());

drop policy if exists "chat_members_admin_update" on public.chat_members;
create policy "chat_members_admin_update" on public.chat_members for update
  to authenticated
  using (public.is_parish_admin())
  with check (public.is_parish_admin());

drop policy if exists "chat_members_admin_delete" on public.chat_members;
create policy "chat_members_admin_delete" on public.chat_members for delete
  to authenticated
  using (public.is_parish_admin());

-- messages
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select
  to authenticated
  using (
    public.can_read_chat(chat_id)
    and (deleted_at is null or author_id = public.current_profile_id() or public.is_parish_admin())
  );

drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert
  to authenticated
  with check (
    author_id = public.current_profile_id()
    and deleted_at is null
    and public.can_post_chat(chat_id)
  );

drop policy if exists "messages_update_own" on public.messages;
create policy "messages_update_own" on public.messages for update
  to authenticated
  using (author_id = public.current_profile_id())
  with check (author_id = public.current_profile_id());

-- Leaders/admins may moderate (soft-delete) messages in chats they oversee.
drop policy if exists "messages_moderate" on public.messages;
create policy "messages_moderate" on public.messages for update
  to authenticated
  using (public.is_chat_leader(chat_id) or (public.is_parish_admin() and public.can_read_chat(chat_id)))
  with check (public.is_chat_leader(chat_id) or (public.is_parish_admin() and public.can_read_chat(chat_id)));

-- message_reactions
drop policy if exists "reactions_select" on public.message_reactions;
create policy "reactions_select" on public.message_reactions for select
  to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id and public.can_read_chat(m.chat_id)
  ));

drop policy if exists "reactions_insert_own" on public.message_reactions;
create policy "reactions_insert_own" on public.message_reactions for insert
  to authenticated
  with check (
    user_id = public.current_profile_id()
    and exists (
      select 1 from public.messages m
      where m.id = message_reactions.message_id and public.can_post_chat(m.chat_id)
    )
  );

drop policy if exists "reactions_delete_own" on public.message_reactions;
create policy "reactions_delete_own" on public.message_reactions for delete
  to authenticated using (user_id = public.current_profile_id());

-- pinned_messages
drop policy if exists "pinned_select" on public.pinned_messages;
create policy "pinned_select" on public.pinned_messages for select
  to authenticated using (public.can_read_chat(chat_id));

drop policy if exists "pinned_write" on public.pinned_messages;
create policy "pinned_write" on public.pinned_messages for all
  to authenticated
  using (public.is_chat_leader(chat_id) or public.is_parish_admin())
  with check (public.is_chat_leader(chat_id) or public.is_parish_admin());

-- ---------------------------------------------------------------------------
-- Realtime: clients subscribe to messages, reactions, and membership changes.
-- The supabase_realtime publication pre-exists on hosted Supabase (and may be
-- owned by another role), so each step is guarded and tolerant of a permission
-- error: if an add fails, it logs a NOTICE rather than aborting the migration
-- (the table can then be enabled from the dashboard's Realtime page).
-- ---------------------------------------------------------------------------

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      create publication supabase_realtime;
    exception when others then
      raise notice 'realtime: could not create publication: %', sqlerrm;
    end;
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['messages','message_reactions','chat_members'] loop
    begin
      if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
         and not exists (select 1 from pg_publication_tables
                         where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    exception when others then
      raise notice 'realtime: could not add %: %', t, sqlerrm;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Edge-function hooks (configured as Database Webhooks in Supabase, not here):
--   * AFTER INSERT ON messages -> `send-push`        (Expo push fan-out)
--   * AFTER INSERT ON messages -> `moderate-message` (OpenAI moderation; soft
--                                                      delete + moderation_log)
-- The moderation_log table lands in 0009_safety.sql.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Seed: the parish announcements channel and the 7 house group chats.
-- Fixed UUIDs, idempotent. House UUIDs come from 0001_init_identity.sql.
-- ---------------------------------------------------------------------------

insert into public.chats (id, kind, parish_id, house_id) values
  ('0000000c-0000-0000-0000-000000000000', 'announcements', '00000000-0000-0000-0000-000000000001', null),
  ('0000000c-0000-0000-0000-0000000000b1', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1'),
  ('0000000c-0000-0000-0000-0000000000a1', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1'),
  ('0000000c-0000-0000-0000-0000000000be', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000be'),
  ('0000000c-0000-0000-0000-0000000000b2', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b2'),
  ('0000000c-0000-0000-0000-0000000000c1', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c1'),
  ('0000000c-0000-0000-0000-0000000000d1', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1'),
  ('0000000c-0000-0000-0000-0000000000e1', 'house_group',   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e1')
on conflict (id) do nothing;

-- ===================== 0007_prayer_wall.sql =====================
-- 0007_prayer_wall.sql
-- Prayer wall: requests (house-scoped or parish-wide), "I prayed" taps, and
-- reactions. House leaders see every request in their house for pastoral care,
-- including anonymous ones (the anonymous flag hides identity in the UI, not
-- from the leader's duty of care).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.prayer_requests (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  house_id    uuid references public.houses(id) on delete set null,  -- null => parish-wide
  author_id   uuid not null references public.user_profiles(id) on delete cascade,
  body        text not null,
  anonymous   boolean not null default false,
  urgent      boolean not null default false,
  praise      boolean not null default false,   -- praise report vs request
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists public.prayer_pray (
  request_id uuid not null references public.prayer_requests(id) on delete cascade,
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

create table if not exists public.prayer_reactions (
  request_id uuid not null references public.prayer_requests(id) on delete cascade,
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  emoji      text not null check (emoji in ('🙏', '❤️', 'amen', '🔥', '✋')),
  created_at timestamptz not null default now(),
  primary key (request_id, user_id, emoji)
);

create index if not exists idx_prayer_requests_scope on public.prayer_requests (parish_id, house_id, created_at desc);
create index if not exists idx_prayer_pray_request on public.prayer_pray (request_id);
create index if not exists idx_prayer_reactions_request on public.prayer_reactions (request_id);

-- ---------------------------------------------------------------------------
-- Visibility helper (SECURITY DEFINER): can the caller see this request?
-- ---------------------------------------------------------------------------

create or replace function public.can_read_prayer(p_request uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.prayer_requests r
    where r.id = p_request
      and r.parish_id = public.current_parish_id()
      and (
           r.house_id is null                                   -- parish-wide
        or r.house_id = public.current_house_id()               -- your house
        or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = r.house_id)
        or public.is_parish_admin()
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.prayer_requests  enable row level security;
alter table public.prayer_pray      enable row level security;
alter table public.prayer_reactions enable row level security;

-- Read: parish-wide requests to all parish members; house requests to that
-- house (members + leader), plus parish admins.
drop policy if exists "prayer_requests_select" on public.prayer_requests;
create policy "prayer_requests_select" on public.prayer_requests for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
         house_id is null
      or house_id = public.current_house_id()
      or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
      or public.is_parish_admin()
    )
  );

-- Insert: your own request, in your parish, scoped to your house or parish-wide.
drop policy if exists "prayer_requests_insert_own" on public.prayer_requests;
create policy "prayer_requests_insert_own" on public.prayer_requests for insert
  to authenticated
  with check (
    author_id = public.current_profile_id()
    and parish_id = public.current_parish_id()
    and (house_id is null or house_id = public.current_house_id())
  );

-- Update (archive / edit): author, the house leader, or a parish admin.
drop policy if exists "prayer_requests_update" on public.prayer_requests;
create policy "prayer_requests_update" on public.prayer_requests for update
  to authenticated
  using (
    author_id = public.current_profile_id()
    or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
    or public.is_parish_admin()
  )
  with check (
    author_id = public.current_profile_id()
    or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
    or public.is_parish_admin()
  );

-- Author may delete their own request.
drop policy if exists "prayer_requests_delete_own" on public.prayer_requests;
create policy "prayer_requests_delete_own" on public.prayer_requests for delete
  to authenticated
  using (author_id = public.current_profile_id());

-- prayer_pray: see taps on visible requests; record/remove your own tap.
drop policy if exists "prayer_pray_select" on public.prayer_pray;
create policy "prayer_pray_select" on public.prayer_pray for select
  to authenticated using (public.can_read_prayer(request_id));

drop policy if exists "prayer_pray_insert_own" on public.prayer_pray;
create policy "prayer_pray_insert_own" on public.prayer_pray for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_prayer(request_id));

drop policy if exists "prayer_pray_delete_own" on public.prayer_pray;
create policy "prayer_pray_delete_own" on public.prayer_pray for delete
  to authenticated using (user_id = public.current_profile_id());

-- prayer_reactions: same model as taps.
drop policy if exists "prayer_reactions_select" on public.prayer_reactions;
create policy "prayer_reactions_select" on public.prayer_reactions for select
  to authenticated using (public.can_read_prayer(request_id));

drop policy if exists "prayer_reactions_insert_own" on public.prayer_reactions;
create policy "prayer_reactions_insert_own" on public.prayer_reactions for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_prayer(request_id));

drop policy if exists "prayer_reactions_delete_own" on public.prayer_reactions;
create policy "prayer_reactions_delete_own" on public.prayer_reactions for delete
  to authenticated using (user_id = public.current_profile_id());

-- ===================== 0008_ask_pastor.sql =====================
-- 0008_ask_pastor.sql
-- Ask Pastor: a structured queue (NOT a free chat). A disciple submits a
-- question; the pastor answers within the response window, either privately
-- (to the asker) or publicly (anonymized into the public Q&A feed).

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.ask_questions (
  id                uuid primary key default gen_random_uuid(),
  parish_id         uuid not null references public.parishes(id) on delete cascade,
  asker_id          uuid not null references public.user_profiles(id) on delete cascade,
  body              text not null,
  category          text,
  privacy           text not null default 'private'
                      check (privacy in ('public', 'private')),
  urgent            boolean not null default false,
  status            text not null default 'awaiting'
                      check (status in ('awaiting', 'answered')),
  response_body     text,
  answered_by       uuid references public.user_profiles(id) on delete set null,
  answered_at       timestamptz,
  public_anonymized boolean not null default true,
  created_at        timestamptz not null default now()
);

create index if not exists idx_ask_questions_parish_status on public.ask_questions (parish_id, status, created_at desc);
create index if not exists idx_ask_questions_asker on public.ask_questions (asker_id, created_at desc);
create index if not exists idx_ask_questions_public
  on public.ask_questions (parish_id, answered_at desc)
  where status = 'answered' and privacy = 'public';

-- ---------------------------------------------------------------------------
-- Public Q&A feed: answered, public questions with the asker anonymized.
-- This is a SECURITY DEFINER view (the default): it reads the base table as the
-- view owner and exposes ONLY non-identifying columns, scoped to the caller's
-- parish. This is deliberate: the base table never grants other members a row
-- that carries asker_id, so "public" truly means anonymized.
-- ---------------------------------------------------------------------------

create or replace view public.public_qa as
  select
    id,
    parish_id,
    category,
    body          as question,
    response_body as answer,
    answered_at
  from public.ask_questions
  where status = 'answered'
    and privacy = 'public'
    and parish_id = public.current_parish_id();

grant select on public.public_qa to authenticated;

-- ---------------------------------------------------------------------------
-- answer_question(): pastor/admin answers a question atomically.
-- ---------------------------------------------------------------------------

create or replace function public.answer_question(
  p_id text,
  p_response text,
  p_public boolean default false
)
returns public.ask_questions
language plpgsql
security definer
set search_path = public
as $$
declare
  q public.ask_questions;
begin
  if not public.is_parish_admin() then
    raise exception 'only pastor/admin may answer questions';
  end if;

  update public.ask_questions
    set response_body = p_response,
        privacy       = case when p_public then 'public' else 'private' end,
        status        = 'answered',
        answered_by   = public.current_profile_id(),
        answered_at   = now()
    where id = p_id::uuid
      and parish_id = public.current_parish_id()
    returning * into q;

  if q.id is null then
    raise exception 'question not found in your parish';
  end if;
  return q;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.ask_questions enable row level security;

-- Asker sees their own questions (any status).
drop policy if exists "ask_questions_select_own" on public.ask_questions;
create policy "ask_questions_select_own" on public.ask_questions for select
  to authenticated
  using (asker_id = public.current_profile_id());

-- Parish admins (pastor/admin) see the whole queue for their parish.
drop policy if exists "ask_questions_select_admin" on public.ask_questions;
create policy "ask_questions_select_admin" on public.ask_questions for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- NOTE: there is deliberately no base-table policy exposing public questions to
-- other members. The anonymized public Q&A feed is served by the public_qa view
-- above, so asker identity never leaks through the raw row.

-- Asker submits their own question (always starts unanswered).
drop policy if exists "ask_questions_insert_own" on public.ask_questions;
create policy "ask_questions_insert_own" on public.ask_questions for insert
  to authenticated
  with check (
    asker_id = public.current_profile_id()
    and parish_id = public.current_parish_id()
    and status = 'awaiting'
    and response_body is null
  );

-- Asker may withdraw a still-unanswered question.
drop policy if exists "ask_questions_delete_own" on public.ask_questions;
create policy "ask_questions_delete_own" on public.ask_questions for delete
  to authenticated
  using (asker_id = public.current_profile_id() and status = 'awaiting');

-- Pastor/admin answer (update) questions in their parish.
drop policy if exists "ask_questions_update_admin" on public.ask_questions;
create policy "ask_questions_update_admin" on public.ask_questions for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ===================== 0009_safety.sql =====================
-- 0009_safety.sql
-- Safety & moderation: blocks, reports, and the moderation log. Block/report/
-- mute must be one tap from any chat surface (pastoral guardrail), so the
-- tables are simple and the block actually hides content at the row level.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.blocks (
  blocker_id uuid not null references public.user_profiles(id) on delete cascade,
  blocked_id uuid not null references public.user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  reporter_id uuid not null references public.user_profiles(id) on delete cascade,
  target_type text not null check (target_type in ('message', 'user', 'prayer_request', 'ask_question')),
  target_id   uuid not null,
  reason      text,
  status      text not null default 'open'
                check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  resolved_by uuid references public.user_profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- Written by the moderate-message edge function (service role); read by admins.
create table if not exists public.moderation_log (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid references public.messages(id) on delete set null,
  flag         text not null,                 -- e.g. 'harassment', 'self-harm'
  severity     text not null default 'low'
                 check (severity in ('low', 'medium', 'high')),
  action_taken text not null default 'logged'
                 check (action_taken in ('logged', 'soft_deleted', 'escalated')),
  created_at   timestamptz not null default now()
);

create index if not exists idx_blocks_blocker on public.blocks (blocker_id);
create index if not exists idx_reports_parish_status on public.reports (parish_id, status, created_at desc);
create index if not exists idx_moderation_log_message on public.moderation_log (message_id);

-- ---------------------------------------------------------------------------
-- Block helper
-- ---------------------------------------------------------------------------

create or replace function public.is_blocked_by_me(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks b
    where b.blocker_id = public.current_profile_id() and b.blocked_id = p_target
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.blocks         enable row level security;
alter table public.reports        enable row level security;
alter table public.moderation_log enable row level security;

-- Blocks: you manage your own block list.
drop policy if exists "blocks_own" on public.blocks;
create policy "blocks_own" on public.blocks for all
  to authenticated
  using (blocker_id = public.current_profile_id())
  with check (blocker_id = public.current_profile_id());

-- Reports: file your own; see your own; admins see + resolve their parish's.
drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own" on public.reports for insert
  to authenticated
  with check (reporter_id = public.current_profile_id() and parish_id = public.current_parish_id());

drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own" on public.reports for select
  to authenticated
  using (reporter_id = public.current_profile_id());

drop policy if exists "reports_select_admin" on public.reports;
create policy "reports_select_admin" on public.reports for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

drop policy if exists "reports_update_admin" on public.reports;
create policy "reports_update_admin" on public.reports for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Moderation log: parish admins read; only the service role writes.
drop policy if exists "moderation_log_select_admin" on public.moderation_log;
create policy "moderation_log_select_admin" on public.moderation_log for select
  to authenticated
  using (public.is_parish_admin());

-- ---------------------------------------------------------------------------
-- Blocking hides content: a RESTRICTIVE policy AND-ed with the permissive
-- message policies so a blocker never sees a blocked user's messages.
-- ---------------------------------------------------------------------------

drop policy if exists "messages_hide_blocked" on public.messages;
create policy "messages_hide_blocked" on public.messages as restrictive for select
  to authenticated
  using (author_id is null or not public.is_blocked_by_me(author_id));

-- ===================== 0010_notifications.sql =====================
-- 0010_notifications.sql
-- Notifications: Expo push tokens, the in-app notification feed, and per-type
-- delivery preferences. In-app notification rows are created by triggers (and
-- the daily-content-publish job); the send-push edge function fans them out to
-- Expo, consulting notification_preferences before pushing.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.push_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  expo_token text unique not null,
  platform   text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  type       text not null
               check (type in ('message', 'announcement', 'ask_answered',
                               'mention', 'daily_prompt', 'streak', 'prayer', 'system')),
  title      text not null,
  preview    text,
  target_id  uuid,        -- chat_id / question_id / prayer_id, etc.
  target_url text,        -- optional deep link (e.g. 'mathetes://chat/<id>')
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create table if not exists public.notification_preferences (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  type    text not null,
  channel text not null check (channel in ('push', 'in_app')),
  enabled boolean not null default true,
  primary key (user_id, type, channel)
);

create index if not exists idx_push_tokens_user on public.push_tokens (user_id);
create index if not exists idx_notifications_user_unread
  on public.notifications (user_id, created_at desc) where read_at is null;
create index if not exists idx_notifications_user on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Notification creation helpers (SECURITY DEFINER: triggers create rows for
-- OTHER users, which RLS would otherwise forbid).
-- ---------------------------------------------------------------------------

create or replace function public.create_notification(
  p_user uuid, p_type text, p_title text,
  p_preview text default null, p_target_id uuid default null, p_target_url text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- Honour an explicit in-app opt-out for this type.
  if exists (
    select 1 from public.notification_preferences
    where user_id = p_user and type = p_type and channel = 'in_app' and enabled = false
  ) then
    return;
  end if;

  insert into public.notifications (user_id, type, title, preview, target_id, target_url)
  values (p_user, p_type, p_title, p_preview, p_target_id, p_target_url);
end;
$$;

-- New message -> notify the other participants (or, for announcements, the
-- whole parish), skipping the author and anyone who muted the chat.
create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_kind   text;
  v_parish uuid;
  v_house  uuid;
  v_title  text;
  v_type   text;
  v_preview text;
begin
  if new.deleted_at is not null or new.kind = 'system' then
    return new;
  end if;

  select kind, parish_id, house_id into v_kind, v_parish, v_house
    from public.chats where id = new.chat_id;

  v_preview := left(coalesce(new.body, case new.kind when 'voice' then 'Voice note'
                                                     when 'image' then 'Photo' else '' end), 140);

  if v_kind = 'announcements' then
    v_type := 'announcement';
    v_title := 'Parish announcement';
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, v_type, v_title, v_preview, new.chat_id, 'mathetes://chat/' || new.chat_id
    from public.user_profiles p
    where p.parish_id = v_parish
      and p.id <> coalesce(new.author_id, '00000000-0000-0000-0000-000000000000')
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = v_type and np.channel = 'in_app' and np.enabled = false
      );
  else
    v_type := case when new.kind = 'daily_prompt' then 'daily_prompt' else 'message' end;
    v_title := case when new.kind = 'daily_prompt' then 'Today''s prompt' else 'New message' end;
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select m.user_id, v_type, v_title, v_preview, new.chat_id, 'mathetes://chat/' || new.chat_id
    from public.chat_members m
    where m.chat_id = new.chat_id
      and m.muted = false
      and m.user_id <> coalesce(new.author_id, '00000000-0000-0000-0000-000000000000')
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = m.user_id and np.type = v_type and np.channel = 'in_app' and np.enabled = false
      );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_message on public.messages;
create trigger trg_notify_on_message
  after insert on public.messages
  for each row execute function public.notify_on_message();

-- Ask-pastor answered -> notify the asker.
create or replace function public.notify_on_answer()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'answered' and (old.status is distinct from 'answered') then
    perform public.create_notification(
      new.asker_id, 'ask_answered', 'Pastor answered your question',
      left(coalesce(new.response_body, ''), 140), new.id, 'mathetes://ask-pastor/' || new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_answer on public.ask_questions;
create trigger trg_notify_on_answer
  after update of status on public.ask_questions
  for each row execute function public.notify_on_answer();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.push_tokens              enable row level security;
alter table public.notifications            enable row level security;
alter table public.notification_preferences enable row level security;

-- Push tokens: register / read / remove your own device tokens.
drop policy if exists "push_tokens_own" on public.push_tokens;
create policy "push_tokens_own" on public.push_tokens for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Notifications: read your own; mark them read (UPDATE). Rows are created by
-- SECURITY DEFINER triggers / the service role, never directly by a member.
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications for select
  to authenticated
  using (user_id = public.current_profile_id());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications for update
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications for delete
  to authenticated
  using (user_id = public.current_profile_id());

-- Preferences: manage your own.
drop policy if exists "notification_preferences_own" on public.notification_preferences;
create policy "notification_preferences_own" on public.notification_preferences for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- ---------------------------------------------------------------------------
-- Realtime: clients live-update the notification bell.
-- ---------------------------------------------------------------------------

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      create publication supabase_realtime;
    exception when others then raise notice 'realtime: could not create publication: %', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
    begin
      alter publication supabase_realtime add table public.notifications;
    exception when others then raise notice 'realtime: could not add notifications: %', sqlerrm;
    end;
  end if;
end $$;

-- ===================== 0011_verse_images.sql =====================
-- 0011_verse_images.sql
-- Verse image generator gallery. Images are rendered server-side (@vercel/og in
-- the admin app), cached in the public `verse-images` storage bucket, and a row
-- is recorded here per generation for the user's personal gallery.

create table if not exists public.verse_images (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.user_profiles(id) on delete cascade,
  verse_ref    text not null,
  verse_text   text not null,
  theme        text not null default 'minimal'
                 check (theme in ('minimal', 'organic', 'bold')),
  aspect_ratio text not null default 'square'
                 check (aspect_ratio in ('square', 'story')),
  watermark    boolean not null default true,
  url          text not null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_verse_images_user on public.verse_images (user_id, created_at desc);

alter table public.verse_images enable row level security;

-- A user's gallery is private to them.
drop policy if exists "verse_images_own" on public.verse_images;
create policy "verse_images_own" on public.verse_images for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- ===================== 0012_bible_search_tuning.sql =====================
-- 0012_bible_search_tuning.sql
-- Refine search_bible ranking. English full-text search drops common stop words
-- ('not', 'unto', ...) and stems aggressively, so a phrase like "lean not unto"
-- reduces to just 'lean' and ranks by term frequency (e.g. Isaiah 24:16's
-- repeated "leanness" outranks Proverbs 3:5). Add a literal phrase-substring
-- boost so verses that actually contain the typed phrase sort first, while
-- still returning the broader full-text matches below them.
--
-- The ILIKE is evaluated only over the GIN-filtered match set, so it stays cheap.

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
  order by
    (v.text ilike '%' || query || '%') desc,   -- exact phrase first
    ts_rank(v.search_vector, websearch_to_tsquery('english', query)) desc,
    b.book_order, c.number, v.number
  limit greatest(max_results, 1);
$$;

-- ===================== 0013_storage.sql =====================
-- 0013_storage.sql
-- Storage buckets + RLS for profile photos, devotional images, and verse
-- images. The cloud project was provisioned via psql (not the Supabase CLI), so
-- config.toml's bucket definitions were never created there; this migration
-- makes the buckets and their access rules reproducible in SQL.
--
-- Convention: a user's files live under a folder named for their auth UID, e.g.
-- 'avatars/<auth_uid>/photo.jpg'. Policies enforce that you may only write into
-- your own folder. Idempotent (drop-if-exists before create) so it is safe to
-- re-run against an existing project.

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',           'avatars',           false,  5242880, array['image/png','image/jpeg','image/webp']),
  ('devotional-images', 'devotional-images', true,  10485760, array['image/png','image/jpeg','image/webp']),
  ('verse-images',      'verse-images',      true,  10485760, array['image/png','image/jpeg'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- avatars: any authenticated user may read; you write only your own folder.
-- (Default photo is initials; uploads are opt-in — see the pastoral guardrails.)
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_avatars_read"        on storage.objects;
drop policy if exists "mathetes_avatars_insert_own"  on storage.objects;
drop policy if exists "mathetes_avatars_update_own"  on storage.objects;
drop policy if exists "mathetes_avatars_delete_own"  on storage.objects;

drop policy if exists "mathetes_avatars_read" on storage.objects;
create policy "mathetes_avatars_read" on storage.objects for select
  to authenticated
  using (bucket_id = 'avatars');

drop policy if exists "mathetes_avatars_insert_own" on storage.objects;
create policy "mathetes_avatars_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_avatars_update_own" on storage.objects;
create policy "mathetes_avatars_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_avatars_delete_own" on storage.objects;
create policy "mathetes_avatars_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- verse-images: public bucket (served by public URL); authenticated users write
-- only their own folder, mirroring the verse_images gallery rows.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_verse_images_read"       on storage.objects;
drop policy if exists "mathetes_verse_images_insert_own" on storage.objects;
drop policy if exists "mathetes_verse_images_update_own" on storage.objects;
drop policy if exists "mathetes_verse_images_delete_own" on storage.objects;

drop policy if exists "mathetes_verse_images_read" on storage.objects;
create policy "mathetes_verse_images_read" on storage.objects for select
  using (bucket_id = 'verse-images');

drop policy if exists "mathetes_verse_images_insert_own" on storage.objects;
create policy "mathetes_verse_images_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_verse_images_update_own" on storage.objects;
create policy "mathetes_verse_images_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_verse_images_delete_own" on storage.objects;
create policy "mathetes_verse_images_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- devotional-images: public read; only pastor/admin may write parish content.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_devo_images_read"  on storage.objects;
drop policy if exists "mathetes_devo_images_write" on storage.objects;

drop policy if exists "mathetes_devo_images_read" on storage.objects;
create policy "mathetes_devo_images_read" on storage.objects for select
  using (bucket_id = 'devotional-images');

drop policy if exists "mathetes_devo_images_write" on storage.objects;
create policy "mathetes_devo_images_write" on storage.objects for all
  to authenticated
  using (bucket_id = 'devotional-images' and public.is_parish_admin())
  with check (bucket_id = 'devotional-images' and public.is_parish_admin());

-- ===================== 0014_announcements.sql =====================
-- 0014_announcements.sql
-- Parish announcements as a content table (authored from the admin dashboard).
-- The canonical schema (CLAUDE.md) lists announcements as content alongside
-- devotionals / word_of_day; the admin app writes to this table. (The chat
-- 'announcements' channel from 0006 remains for the in-app read feed; a trigger
-- here mirrors a published announcement into per-member notifications.)

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  parish_id    uuid not null references public.parishes(id) on delete cascade,
  title        text not null,
  body_md      text not null default '',
  event_data   jsonb,                              -- { date, time, location }
  banner       text check (banner in ('event', 'urgent')),
  photos       text[] not null default '{}',
  status       text not null default 'draft'
                 check (status in ('draft', 'scheduled', 'published')),
  publish_date date,
  posted_at    timestamptz,
  posted_by    uuid references public.user_profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_announcements_parish_status_date
  on public.announcements (parish_id, status, publish_date desc);

-- ---------------------------------------------------------------------------
-- RLS: parish members read published (dated today or earlier); pastor/admin
-- manage and see drafts/scheduled. Mirrors the devotionals / word_of_day model.
-- ---------------------------------------------------------------------------

alter table public.announcements enable row level security;

drop policy if exists "announcements_select_published" on public.announcements;
create policy "announcements_select_published" on public.announcements for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status = 'published' and (publish_date is null or publish_date <= current_date))
      or public.is_parish_admin()
    )
  );

drop policy if exists "announcements_admin_write" on public.announcements;
create policy "announcements_admin_write" on public.announcements for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ---------------------------------------------------------------------------
-- Notify the parish when an announcement is published (transition to
-- 'published'). Reuses the notifications table from 0010. Author is skipped and
-- members are not re-notified for the same announcement.
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_announcement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published'
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'announcement', coalesce(nullif(new.title, ''), 'Parish announcement'),
           left(new.body_md, 140), new.id, 'mathetes://announcements/' || new.id
    from public.user_profiles p
    where p.parish_id = new.parish_id
      and p.id is distinct from new.posted_by
      and not exists (
        select 1 from public.notifications n
        where n.type = 'announcement' and n.target_id = new.id and n.user_id = p.id
      )
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = 'announcement' and np.channel = 'in_app' and np.enabled = false
      );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_announcement on public.announcements;
create trigger trg_notify_on_announcement
  after insert or update of status on public.announcements
  for each row execute function public.notify_on_announcement();

-- ===================== 0015_chat_media.sql =====================
-- 0015_chat_media.sql
-- Storage for chat message media (images and voice notes), plus a fix that
-- makes the avatars bucket public.
--
-- Why avatars becomes public: the Mathetes apps reference profile photos and
-- chat media by their public object URL (storage getPublicUrl). A private
-- bucket only serves bytes through authenticated/signed requests, so the stored
-- public URLs 404. Profile photos are opt-in and chat media filenames are
-- unguessable (uploaded under the author's auth-UID folder), so public buckets
-- with random paths are an acceptable pilot tradeoff. Tighten to signed URLs
-- later if stricter privacy is required.

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------

update storage.buckets set public = true where id = 'avatars';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('chat-media', 'chat-media', true, 26214400,
   array['image/png','image/jpeg','image/webp',
         'audio/m4a','audio/mp4','audio/mpeg','audio/aac','audio/x-m4a'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- chat-media: public read (served by URL); authenticated users write only into
-- their own auth-UID folder, mirroring the avatars / verse-images convention.
-- Who may see a given message is governed by the messages RLS (can_read_chat);
-- this bucket just stores the bytes.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_chat_media_read"       on storage.objects;
drop policy if exists "mathetes_chat_media_insert_own" on storage.objects;
drop policy if exists "mathetes_chat_media_update_own" on storage.objects;
drop policy if exists "mathetes_chat_media_delete_own" on storage.objects;

drop policy if exists "mathetes_chat_media_read" on storage.objects;
create policy "mathetes_chat_media_read" on storage.objects for select
  using (bucket_id = 'chat-media');

drop policy if exists "mathetes_chat_media_insert_own" on storage.objects;
create policy "mathetes_chat_media_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_chat_media_update_own" on storage.objects;
create policy "mathetes_chat_media_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mathetes_chat_media_delete_own" on storage.objects;
create policy "mathetes_chat_media_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ===================== 0016_campuses.sql =====================
-- 0016_campuses.sql
-- Campuses within a parish. The pilot parish (CCCFSP FUOYE) spans two physical
-- campuses, Oye (main) and Ikole. We keep ONE parish with shared houses and
-- content, and tag each member with their campus. This lets the directory,
-- analytics, and (later) campus-scoped announcements distinguish the two
-- without splitting the fellowship. Houses remain parish-wide so a house
-- fellowship stays one body across campuses.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.campuses (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  slug        text not null,
  name        text not null,
  is_primary  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (parish_id, slug)
);

create index if not exists idx_campuses_parish on public.campuses (parish_id);

-- Members carry the campus they attend (nullable until chosen in onboarding).
alter table public.user_profiles
  add column if not exists campus_id uuid references public.campuses(id) on delete set null;

create index if not exists idx_user_profiles_campus on public.user_profiles (campus_id);

-- ---------------------------------------------------------------------------
-- RLS: parish members read their parish's campuses; admins manage them.
-- ---------------------------------------------------------------------------

alter table public.campuses enable row level security;

drop policy if exists "campuses_select_parish" on public.campuses;
create policy "campuses_select_parish" on public.campuses for select
  to authenticated
  using (parish_id = public.current_parish_id());

drop policy if exists "campuses_admin_write" on public.campuses;
create policy "campuses_admin_write" on public.campuses for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ---------------------------------------------------------------------------
-- Seed: the two FUOYE campuses for the pilot parish. Fixed UUIDs, idempotent.
-- (Parish UUID from 0001_init_identity.sql.)
-- ---------------------------------------------------------------------------

insert into public.campuses (id, parish_id, slug, name, is_primary) values
  ('00000000-0000-0000-0000-0000000ca401', '00000000-0000-0000-0000-000000000001', 'oye',   'Oye Campus',   true),
  ('00000000-0000-0000-0000-0000000ca402', '00000000-0000-0000-0000-000000000001', 'ikole', 'Ikole Campus', false)
on conflict (parish_id, slug) do nothing;

