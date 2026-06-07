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
create policy "chats_select" on public.chats for select
  to authenticated using (public.can_read_chat(id));

-- Members create DM/ask-pastor chats through SECURITY DEFINER RPCs; admins may
-- create/manage parish chats directly. These are write-only policies (no FOR
-- ALL) so admin write access never doubles as blanket SELECT on private chats.
create policy "chats_admin_insert" on public.chats for insert
  to authenticated
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "chats_admin_update" on public.chats for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "chats_admin_delete" on public.chats for delete
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- chat_members
create policy "chat_members_select" on public.chat_members for select
  to authenticated using (public.can_read_chat(chat_id));

-- Update only your own membership (last_read_at, mute).
create policy "chat_members_update_own" on public.chat_members for update
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Self-join readable group/announcement chats; leave your own membership.
create policy "chat_members_insert_self" on public.chat_members for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_chat(chat_id));

create policy "chat_members_delete_self" on public.chat_members for delete
  to authenticated using (user_id = public.current_profile_id());

-- Admin membership management is write-only (no FOR ALL): admins never gain a
-- blanket SELECT over private chat memberships (e.g. who DMs whom).
create policy "chat_members_admin_insert" on public.chat_members for insert
  to authenticated
  with check (public.is_parish_admin());

create policy "chat_members_admin_update" on public.chat_members for update
  to authenticated
  using (public.is_parish_admin())
  with check (public.is_parish_admin());

create policy "chat_members_admin_delete" on public.chat_members for delete
  to authenticated
  using (public.is_parish_admin());

-- messages
create policy "messages_select" on public.messages for select
  to authenticated
  using (
    public.can_read_chat(chat_id)
    and (deleted_at is null or author_id = public.current_profile_id() or public.is_parish_admin())
  );

create policy "messages_insert" on public.messages for insert
  to authenticated
  with check (
    author_id = public.current_profile_id()
    and deleted_at is null
    and public.can_post_chat(chat_id)
  );

create policy "messages_update_own" on public.messages for update
  to authenticated
  using (author_id = public.current_profile_id())
  with check (author_id = public.current_profile_id());

-- Leaders/admins may moderate (soft-delete) messages in chats they oversee.
create policy "messages_moderate" on public.messages for update
  to authenticated
  using (public.is_chat_leader(chat_id) or (public.is_parish_admin() and public.can_read_chat(chat_id)))
  with check (public.is_chat_leader(chat_id) or (public.is_parish_admin() and public.can_read_chat(chat_id)));

-- message_reactions
create policy "reactions_select" on public.message_reactions for select
  to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id and public.can_read_chat(m.chat_id)
  ));

create policy "reactions_insert_own" on public.message_reactions for insert
  to authenticated
  with check (
    user_id = public.current_profile_id()
    and exists (
      select 1 from public.messages m
      where m.id = message_reactions.message_id and public.can_post_chat(m.chat_id)
    )
  );

create policy "reactions_delete_own" on public.message_reactions for delete
  to authenticated using (user_id = public.current_profile_id());

-- pinned_messages
create policy "pinned_select" on public.pinned_messages for select
  to authenticated using (public.can_read_chat(chat_id));

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
