-- 0045_circles_and_prayer_meetings.sql
--
-- Student-created Circles are private, parish-scoped groups. The chat record
-- remains the single source of truth for membership and messages; this adds
-- editable Circle metadata, owner/admin roles, and private audio/video prayer
-- meetings. LiveKit access is issued by a separate Edge Function only after it
-- verifies an active Circle membership.

-- ---------------------------------------------------------------------------
-- Chat metadata and Circle roles
-- ---------------------------------------------------------------------------

alter table public.chats
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists image_url text,
  add column if not exists max_members integer not null default 50,
  add column if not exists archived_at timestamptz;

alter table public.chats drop constraint if exists chats_kind_check;
alter table public.chats add constraint chats_kind_check
  check (kind in ('house_group', 'announcements', 'ask_pastor_thread',
                 'discipler', 'dm', 'parish_group', 'circle'));

alter table public.chats drop constraint if exists chats_max_members_check;
alter table public.chats add constraint chats_max_members_check
  check (max_members between 2 and 100);

alter table public.chat_members drop constraint if exists chat_members_role_check;
alter table public.chat_members add constraint chat_members_role_check
  check (role in ('member', 'leader', 'pastor', 'discipler', 'owner', 'admin'));

create index if not exists idx_chats_circle_parish
  on public.chats (parish_id, created_at desc) where kind = 'circle';
create index if not exists idx_chat_members_chat_role
  on public.chat_members (chat_id, role);

-- Circle pictures use a public bucket because the URL is rendered by native
-- clients. Only Circle owners/admins may write into their Circle's folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'circle-images', 'circle-images', true, 5242880,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_circle_admin(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1
    from public.chats c
    join public.chat_members m on m.chat_id = c.id
    where c.id = p_chat
      and c.kind = 'circle'
      and m.user_id = public.current_profile_id()
      and m.role in ('owner', 'admin')
  );
$$;

create or replace function public.can_manage_circle_image(p_path text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.chats c
    join public.chat_members m on m.chat_id = c.id
    where c.kind = 'circle'
      and c.id::text = (storage.foldername(p_path))[1]
      and m.user_id = public.current_profile_id()
      and m.role in ('owner', 'admin')
      and public.is_active_member()
  );
$$;

drop policy if exists "circle images are public" on storage.objects;
create policy "circle images are public" on storage.objects for select
  using (bucket_id = 'circle-images');

drop policy if exists "circle admins upload images" on storage.objects;
create policy "circle admins upload images" on storage.objects for insert to authenticated
  with check (bucket_id = 'circle-images' and public.can_manage_circle_image(name));

drop policy if exists "circle admins update images" on storage.objects;
create policy "circle admins update images" on storage.objects for update to authenticated
  using (bucket_id = 'circle-images' and public.can_manage_circle_image(name))
  with check (bucket_id = 'circle-images' and public.can_manage_circle_image(name));

drop policy if exists "circle admins delete images" on storage.objects;
create policy "circle admins delete images" on storage.objects for delete to authenticated
  using (bucket_id = 'circle-images' and public.can_manage_circle_image(name));

-- Owners and Circle admins can perform ordinary leader actions such as pinning
-- or moderating a message, without giving parish staff visibility into private
-- Circle conversations.
create or replace function public.is_chat_leader(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_members m
    where m.chat_id = p_chat
      and m.user_id = public.current_profile_id()
      and m.role in ('leader', 'pastor', 'owner', 'admin')
  );
$$;

-- Circle history remains readable after an archive, but only members may post
-- while it is active. All other chat guardrails are intentionally unchanged.
create or replace function public.can_post_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         (c.kind = 'announcements' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind in ('dm', 'discipler', 'ask_pastor_thread') and public.is_chat_member(p_chat))
      or (c.kind = 'circle' and c.archived_at is null and public.is_chat_member(p_chat))
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Circle lifecycle RPCs. Direct insert/update of chats remains staff-only;
-- these narrowly-scoped SECURITY DEFINER APIs give members no access to DMs
-- or another parish's members.
-- ---------------------------------------------------------------------------

create or replace function public.create_circle(
  p_title text,
  p_description text default null,
  p_member_ids uuid[] default '{}'::uuid[]
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid := public.current_parish_id();
  v_chat uuid;
  v_count integer;
  v_title text := btrim(coalesce(p_title, ''));
begin
  if not public.is_active_member() then raise exception 'active membership required'; end if;
  if length(v_title) < 2 or length(v_title) > 80 then
    raise exception 'Circle name must be between 2 and 80 characters';
  end if;

  select count(*) into v_count
  from (
    select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id
  ) requested
  join public.user_profiles p on p.id = requested.id
  where p.parish_id = v_parish and p.status = 'active';

  if v_count <> cardinality(array(select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])))) then
    raise exception 'every Circle member must be active and in your parish';
  end if;
  if v_count + 1 > 100 then raise exception 'a Circle can have at most 100 members'; end if;

  insert into public.chats (kind, parish_id, created_by, title, description)
  values ('circle', v_parish, v_me, v_title, nullif(btrim(p_description), ''))
  returning id into v_chat;

  insert into public.chat_members (chat_id, user_id, role)
  values (v_chat, v_me, 'owner');

  insert into public.chat_members (chat_id, user_id, role)
  select v_chat, requested.id, 'member'
  from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested
  where requested.id <> v_me
  on conflict (chat_id, user_id) do nothing;

  insert into public.messages (chat_id, author_id, body, kind)
  values (v_chat, v_me, 'created this Circle.', 'system');

  return v_chat;
end;
$$;

create or replace function public.update_circle(
  p_chat uuid,
  p_title text default null,
  p_description text default null,
  p_image_url text default null,
  p_clear_image boolean default false
)
returns void language plpgsql security definer set search_path = public as $$
declare v_title text := btrim(coalesce(p_title, ''));
begin
  if not public.is_circle_admin(p_chat) then raise exception 'Circle admin required'; end if;
  if p_title is not null and (length(v_title) < 2 or length(v_title) > 80) then
    raise exception 'Circle name must be between 2 and 80 characters';
  end if;

  update public.chats
  set title = case when p_title is null then title else v_title end,
      description = case when p_description is null then description else nullif(btrim(p_description), '') end,
      image_url = case when p_clear_image then null when p_image_url is null then image_url else p_image_url end
  where id = p_chat and kind = 'circle';
end;
$$;

create or replace function public.add_circle_members(p_chat uuid, p_member_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_parish uuid;
  v_new integer;
  v_total integer;
begin
  if not public.is_circle_admin(p_chat) then raise exception 'Circle admin required'; end if;
  select parish_id into v_parish from public.chats where id = p_chat and kind = 'circle' and archived_at is null;
  if v_parish is null then raise exception 'active Circle not found'; end if;

  if exists (
    select 1
    from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested
    left join public.user_profiles p on p.id = requested.id
    where p.id is null or p.parish_id <> v_parish or p.status <> 'active'
  ) then raise exception 'every Circle member must be active and in your parish'; end if;

  select count(*) into v_new
  from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested
  where not exists (select 1 from public.chat_members m where m.chat_id = p_chat and m.user_id = requested.id);
  select count(*) into v_total from public.chat_members where chat_id = p_chat;
  if v_total + v_new > 100 then raise exception 'a Circle can have at most 100 members'; end if;

  insert into public.chat_members (chat_id, user_id, role)
  select p_chat, id, 'member'
  from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested
  on conflict (chat_id, user_id) do nothing;
end;
$$;

create or replace function public.remove_circle_member(p_chat uuid, p_member uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_circle_admin(p_chat) then raise exception 'Circle admin required'; end if;
  if exists (select 1 from public.chat_members where chat_id = p_chat and user_id = p_member and role = 'owner') then
    raise exception 'transfer ownership before removing the Circle owner';
  end if;
  delete from public.chat_members where chat_id = p_chat and user_id = p_member;
end;
$$;

create or replace function public.set_circle_member_role(p_chat uuid, p_member uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.chat_members where chat_id = p_chat
      and user_id = public.current_profile_id() and role = 'owner'
  ) then raise exception 'Circle owner required'; end if;
  if p_role not in ('member', 'admin') then raise exception 'role must be member or admin'; end if;
  update public.chat_members set role = p_role
  where chat_id = p_chat and user_id = p_member and role <> 'owner';
end;
$$;

create or replace function public.transfer_circle_ownership(p_chat uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.current_profile_id();
begin
  if not exists (select 1 from public.chat_members where chat_id = p_chat and user_id = v_me and role = 'owner') then
    raise exception 'Circle owner required';
  end if;
  if not exists (select 1 from public.chat_members where chat_id = p_chat and user_id = p_new_owner) then
    raise exception 'new owner must already be a Circle member';
  end if;
  update public.chat_members set role = 'admin' where chat_id = p_chat and user_id = v_me;
  update public.chat_members set role = 'owner' where chat_id = p_chat and user_id = p_new_owner;
end;
$$;

create or replace function public.leave_circle(p_chat uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.current_profile_id();
begin
  if exists (select 1 from public.chat_members where chat_id = p_chat and user_id = v_me and role = 'owner') then
    raise exception 'transfer ownership before leaving this Circle';
  end if;
  delete from public.chat_members where chat_id = p_chat and user_id = v_me;
end;
$$;

create or replace function public.archive_circle(p_chat uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_circle_admin(p_chat) then raise exception 'Circle admin required'; end if;
  update public.chats set archived_at = now() where id = p_chat and kind = 'circle' and archived_at is null;
end;
$$;

grant execute on function public.create_circle(text, text, uuid[]) to authenticated;
grant execute on function public.update_circle(uuid, text, text, text, boolean) to authenticated;
grant execute on function public.add_circle_members(uuid, uuid[]) to authenticated;
grant execute on function public.remove_circle_member(uuid, uuid) to authenticated;
grant execute on function public.set_circle_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.transfer_circle_ownership(uuid, uuid) to authenticated;
grant execute on function public.leave_circle(uuid) to authenticated;
grant execute on function public.archive_circle(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Prayer meetings. Presence and media travel through LiveKit; this table is
-- only the audited invitation/permission source and never stores recordings.
-- ---------------------------------------------------------------------------

create table if not exists public.circle_meetings (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  parish_id uuid not null references public.parishes(id) on delete cascade,
  created_by uuid references public.user_profiles(id) on delete set null,
  title text not null default 'Prayer meeting',
  mode text not null check (mode in ('audio', 'video')),
  status text not null default 'live' check (status in ('live', 'ended')),
  room_name text not null unique,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists idx_circle_meetings_chat_status
  on public.circle_meetings (chat_id, status, started_at desc);

alter table public.circle_meetings enable row level security;

drop policy if exists "circle meetings visible to members" on public.circle_meetings;
create policy "circle meetings visible to members" on public.circle_meetings for select to authenticated
  using (
    public.is_active_member()
    and parish_id = public.current_parish_id()
    and public.is_chat_member(chat_id)
  );

create or replace function public.create_circle_meeting(
  p_chat uuid,
  p_mode text,
  p_title text default 'Prayer meeting'
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid;
  v_circle_title text;
  v_meeting uuid := gen_random_uuid();
  v_title text := coalesce(nullif(btrim(p_title), ''), 'Prayer meeting');
  v_mode text := lower(coalesce(p_mode, 'audio'));
begin
  if not public.is_circle_admin(p_chat) then raise exception 'Circle admin required'; end if;
  if v_mode not in ('audio', 'video') then raise exception 'meeting mode must be audio or video'; end if;
  if length(v_title) > 100 then raise exception 'meeting title is too long'; end if;

  select parish_id, title into v_parish, v_circle_title
  from public.chats where id = p_chat and kind = 'circle' and archived_at is null;
  if v_parish is null then raise exception 'active Circle not found'; end if;

  -- End a stale live room first: one live prayer room per Circle keeps joining
  -- simple and prevents accidental parallel calls.
  update public.circle_meetings set status = 'ended', ended_at = now()
    where chat_id = p_chat and status = 'live';

  insert into public.circle_meetings (id, chat_id, parish_id, created_by, title, mode, room_name)
  values (v_meeting, p_chat, v_parish, v_me, v_title, v_mode, 'mathetes-' || replace(v_meeting::text, '-', ''));

  perform public.create_notification(
    m.user_id,
    'system',
    coalesce(v_circle_title, 'Your Circle') || ' is live',
    case when v_mode = 'video' then 'A video prayer meeting has started.' else 'An audio prayer meeting has started.' end,
    v_meeting,
    'mathetes://meeting/' || v_meeting
  )
  from public.chat_members m
  where m.chat_id = p_chat and m.user_id <> v_me and m.muted = false;

  return v_meeting;
end;
$$;

create or replace function public.end_circle_meeting(p_meeting uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_chat uuid;
begin
  select chat_id into v_chat from public.circle_meetings where id = p_meeting and status = 'live';
  if v_chat is null then raise exception 'live meeting not found'; end if;
  if not public.is_circle_admin(v_chat) then raise exception 'Circle admin required'; end if;
  update public.circle_meetings set status = 'ended', ended_at = now() where id = p_meeting;
end;
$$;

grant execute on function public.create_circle_meeting(uuid, text, text) to authenticated;
grant execute on function public.end_circle_meeting(uuid) to authenticated;

-- Make live meeting state arrive without a manual refresh. Failure to alter a
-- managed publication is non-fatal; the dashboard can enable it manually.
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'circle_meetings'
  ) then
    alter publication supabase_realtime add table public.circle_meetings;
  end if;
exception when others then
  raise notice 'realtime: could not add circle_meetings: %', sqlerrm;
end $$;
