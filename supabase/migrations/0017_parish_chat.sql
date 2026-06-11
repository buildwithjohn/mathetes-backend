-- 0017_parish_chat.sql
-- A parish-wide general chat room. Unlike the read-only announcements channel,
-- every parish member can read AND post here. One room per parish.

-- ---------------------------------------------------------------------------
-- Allow the new chat kind.
-- ---------------------------------------------------------------------------

alter table public.chats drop constraint if exists chats_kind_check;
alter table public.chats add constraint chats_kind_check
  check (kind in ('house_group', 'announcements', 'ask_pastor_thread',
                  'discipler', 'dm', 'parish_group'));

-- ---------------------------------------------------------------------------
-- Access: add the parish_group clause to the read/post helpers (re-created in
-- full so the definitions stay self-contained). Read + post for any member of
-- the parish; oversight rules for the other kinds are unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.can_read_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         public.is_chat_member(p_chat)
      or (c.kind = 'announcements' and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind = 'ask_pastor_thread' and public.is_parish_admin()
          and c.parish_id = public.current_parish_id())
      or (c.kind = 'dm' and c.house_id is not null
          and public.current_profile_id() = (select h.leader_id from public.houses h where h.id = c.house_id))
      or (c.kind = 'discipler' and c.parish_id = public.current_parish_id()
          and public.current_user_role() = 'pastor')
    )
  );
$$;

create or replace function public.can_post_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         (c.kind = 'announcements' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind in ('dm', 'discipler', 'ask_pastor_thread') and public.is_chat_member(p_chat))
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Seed: one parish_group room for the pilot parish. Fixed UUID, idempotent.
-- ---------------------------------------------------------------------------

insert into public.chats (id, kind, parish_id) values
  ('0000000c-0000-0000-0000-0000000000c0', 'parish_group', '00000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
