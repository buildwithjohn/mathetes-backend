-- 0034_open_dms.sql
-- Policy decision (John, owner): direct messages are FULLY OPEN. Any active
-- parish member may DM any other active parish member. This removes the
-- student-only guardrails that 0020/0021/0033 layered onto create_dm:
--   * cross-house restriction (B1, 0021)              -- removed
--   * cross-gender approval gate  (B2, 0020)          -- removed
--   * role-based "leader reach" branch (0033)         -- no longer needed
--
-- Kept: the target must be in the caller's parish, and must be an active
-- member. Idempotent (an existing DM is returned, never re-gated).
--
-- Note: private-DM oversight was already removed in 0029 (DMs are visible only
-- to their two participants; a reported message surfaces to admins). Opening
-- cross-house DMs therefore does NOT change what leaders can see. The mobile
-- "cross-house"/"cross-gender" error copy simply never fires now.
--
-- Supersedes create_dm from 0033 (append-only; earlier versions left intact).

create or replace function public.create_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me           uuid := public.current_profile_id();
  v_chat         uuid;
  v_parish       uuid;
  v_house        uuid;
  v_other_parish uuid;
  v_other_house  uuid;
  v_other_status text;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  if p_other is null or p_other = v_me then raise exception 'invalid DM target'; end if;

  select parish_id, house_id into v_parish, v_house
    from public.user_profiles where id = v_me;

  select parish_id, house_id, status
    into v_other_parish, v_other_house, v_other_status
    from public.user_profiles where id = p_other;

  -- Same parish still holds for everyone.
  if v_other_parish is null or v_other_parish <> v_parish then
    raise exception 'DM target must be in your parish';
  end if;

  -- Existing DM between exactly these two? Return it (do not re-gate).
  select c.id into v_chat
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = v_me
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = p_other
  where c.kind = 'dm'
  limit 1;
  if v_chat is not null then
    return v_chat;
  end if;

  -- A NEW DM may only target an active member.
  if v_other_status is distinct from 'active' then
    raise exception 'DM target is not an active member';
  end if;

  -- Fully open: no house or cross-gender gate. house_id is kept only when both
  -- happen to share one house (tidy grouping); per 0029 it no longer affects
  -- DM read/post access.
  insert into public.chats (kind, parish_id, house_id, created_by)
    values ('dm', v_parish,
            case when v_house is not null and v_house = v_other_house then v_house else null end,
            v_me)
    returning id into v_chat;

  insert into public.chat_members (chat_id, user_id, role) values
    (v_chat, v_me, 'member'),
    (v_chat, p_other, 'member')
  on conflict do nothing;

  return v_chat;
end;
$$;
