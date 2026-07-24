-- 0052_group_stewardship.sql
-- Operational group stewardship without weakening private conversations.
--
-- A global app owner may administer parish shared spaces and private Circles
-- for safeguarding/continuity. This intentionally excludes DMs, discipler
-- conversations and Ask-Pastor threads: ownership is not a surveillance path.
-- Official House-group membership is still the member's canonical house
-- assignment, never an arbitrary chat-members row.

create or replace function public.can_read_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         public.is_chat_member(p_chat)
      or (
        public.is_owner()
        and c.parish_id = public.current_parish_id()
        and c.kind in ('announcements', 'parish_group', 'house_group', 'circle')
      )
      or (c.kind = 'announcements' and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind = 'ask_pastor_thread' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      or (c.kind = 'discipler' and c.parish_id = public.current_parish_id()
          and public.current_user_role() = 'pastor')
    )
  );
$$;

create or replace function public.can_post_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         (c.kind = 'announcements' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and (
            c.house_id = public.current_house_id()
            or (public.is_owner() and c.parish_id = public.current_parish_id())
          ))
      or (c.kind in ('dm', 'discipler', 'ask_pastor_thread') and public.is_chat_member(p_chat))
      or (c.kind = 'circle' and c.archived_at is null and (
            public.is_chat_member(p_chat)
            or (public.is_owner() and c.parish_id = public.current_parish_id())
          ))
    )
  );
$$;

create or replace function public.is_circle_admin(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1 from public.chats c
    where c.id = p_chat
      and c.kind = 'circle'
      and c.parish_id = public.current_parish_id()
      and (
        public.is_owner()
        or exists (
          select 1 from public.chat_members m
          where m.chat_id = c.id
            and m.user_id = public.current_profile_id()
            and m.role in ('owner', 'admin')
        )
      )
  );
$$;

create or replace function public.can_manage_circle_image(p_path text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chats c
    where c.kind = 'circle'
      and c.id::text = (storage.foldername(p_path))[1]
      and c.parish_id = public.current_parish_id()
      and public.is_active_member()
      and (
        public.is_owner()
        or exists (
          select 1 from public.chat_members m
          where m.chat_id = c.id
            and m.user_id = public.current_profile_id()
            and m.role in ('owner', 'admin')
        )
      )
  );
$$;

create or replace function public.set_circle_member_role(p_chat uuid, p_member uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.chats c
    where c.id = p_chat and c.kind = 'circle' and c.parish_id = public.current_parish_id()
      and (
        public.is_owner()
        or exists (
          select 1 from public.chat_members m
          where m.chat_id = c.id and m.user_id = public.current_profile_id() and m.role = 'owner'
        )
      )
  ) then raise exception 'Circle owner required'; end if;
  if p_role not in ('member', 'admin') then raise exception 'role must be member or admin'; end if;
  update public.chat_members set role = p_role
  where chat_id = p_chat and user_id = p_member and role <> 'owner';
end;
$$;

create or replace function public.assign_house_members(p_house uuid, p_member_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_parish uuid := public.current_parish_id();
  v_requested integer;
  v_eligible integer;
begin
  if not public.is_parish_admin() then raise exception 'parish admin required'; end if;
  if not exists (
    select 1 from public.houses h
    where h.id = p_house and h.parish_id = v_parish
  ) then raise exception 'house must be in your parish'; end if;

  select count(*) into v_requested
  from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested;
  if v_requested = 0 then return; end if;

  select count(*) into v_eligible
  from (select distinct unnest(coalesce(p_member_ids, '{}'::uuid[])) as id) requested
  join public.user_profiles p on p.id = requested.id
  where p.parish_id = v_parish and p.status = 'active';
  if v_eligible <> v_requested then
    raise exception 'every house member must be active and in your parish';
  end if;

  update public.user_profiles
  set house_id = p_house
  where id in (select distinct unnest(p_member_ids));
end;
$$;

grant execute on function public.assign_house_members(uuid, uuid[]) to authenticated;
