-- 0029_dm_no_passive_oversight.sql
-- Pastoral-model decision (John): private 1:1 DMs are NOT a surveillance surface.
-- Oversight belongs on shared spaces — house/parish group chats, announcements,
-- discipler and ask-pastor threads — not on personal direct messages.
--
--   * REMOVE the house-leader "oversight read" of DM content. After this, only
--     the two DM participants can read a DM (and its existence). Leaders and
--     pastors can no longer passively browse anyone's DMs.
--   * KEEP a narrow, consent-driven safety path: when a participant REPORTS a
--     specific DM message, that one message becomes visible to parish admin/
--     pastor so they can act on abuse. Nothing else in the DM is exposed.
--
-- Discipler-chat oversight (pastor) and group/announcement oversight are
-- unchanged — those are accountability/shared surfaces, not private DMs.

-- ---------------------------------------------------------------------------
-- 1. Drop the DM branch from can_read_chat (was the leader's passive oversight).
--    Re-declared from 0025 verbatim minus the `dm` leader clause. The two
--    participants still read via is_chat_member().
-- ---------------------------------------------------------------------------

create or replace function public.can_read_chat(p_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_member() and exists (
    select 1 from public.chats c
    where c.id = p_chat and (
         public.is_chat_member(p_chat)
      or (c.kind = 'announcements' and c.parish_id = public.current_parish_id())
      or (c.kind = 'parish_group' and c.parish_id = public.current_parish_id())
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind = 'ask_pastor_thread' and public.is_parish_admin() and c.parish_id = public.current_parish_id())
      -- (removed) c.kind = 'dm' leader oversight: DMs are private to participants.
      or (c.kind = 'discipler' and c.parish_id = public.current_parish_id()
          and public.current_user_role() = 'pastor')
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. Report path: a parish admin/pastor may read a message ONLY when it has
--    been reported in their parish. This is OR-ed (permissive) with the normal
--    messages_select policy, so it surfaces exactly the flagged message and
--    nothing else — passive DM browsing stays blocked by can_read_chat.
-- ---------------------------------------------------------------------------

drop policy if exists "messages_select_reported" on public.messages;
create policy "messages_select_reported" on public.messages for select
  to authenticated
  using (
    public.is_parish_admin()
    and exists (
      select 1 from public.reports r
      where r.target_type = 'message'
        and r.target_id = messages.id
        and r.parish_id = public.current_parish_id()
    )
  );
