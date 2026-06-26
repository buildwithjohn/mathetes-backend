-- 0033_leader_reach.sql
-- Leader reach for pastoral care. Two by-design student guardrails were also
-- limiting leaders, so leaders (owner / pastor / admin, and disciplers toward
-- their own disciples) could neither see the full parish directory nor DM
-- members outside their own house. This makes both rules ROLE-AWARE while
-- keeping students' conservative defaults unchanged.
--
-- Decision (John, platform owner): private DMs remain non-surveillance (0029);
-- this is about a leader's ability to INITIATE pastoral contact, not to browse.
--
--   1. Directory (user_profiles SELECT): students keep active->active parish
--      visibility (0025). Parish admins (pastor/admin, incl. owner) additionally
--      see every parish profile regardless of status, so the owner/leaders can
--      actually see and manage the whole parish. Append-only permissive policy;
--      0025 + 0027 are left intact and OR-combine with this one.
--
--   2. create_dm: students unchanged (house-mate to house-mate, cross-gender
--      needs approval). Leaders may DM any ACTIVE parish member, cross-house
--      allowed, and bypass cross-gender approval (pastoral care). A discipler
--      gets the same reach toward their OWN disciples only. "Same parish" still
--      holds for everyone. The RPC stays the single source of truth (same
--      signature) so mobile's existing error-copy mapping keeps working.
--
-- Error strings consumed by mobile (app/(auth)/members.tsx) are preserved
-- verbatim for the student path: "must be in your parish", "cross-house DM",
-- "cross-gender DM requires recipient approval".

-- ---------------------------------------------------------------------------
-- 1. Directory: leaders see the whole parish.
-- ---------------------------------------------------------------------------

-- Permissive (OR-ed with user_profiles_select_same_parish from 0025 and
-- user_profiles_admin_pending_select from 0027). Pending signups carry a null
-- parish_id, so 0027 still covers them; this covers in-parish members of any
-- status (active / suspended / rejected) for parish admins.
drop policy if exists "user_profiles_select_leader_directory" on public.user_profiles;
create policy "user_profiles_select_leader_directory" on public.user_profiles for select
  to authenticated
  using (
    public.is_parish_admin()
    and parish_id = public.current_parish_id()
  );

-- ---------------------------------------------------------------------------
-- 2. create_dm: role-aware reach. Authoritative redefinition (supersedes 0021;
--    0006/0020/0021 left intact, append-only).
-- ---------------------------------------------------------------------------

create or replace function public.create_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me              uuid := public.current_profile_id();
  v_chat            uuid;
  v_parish          uuid;
  v_house           uuid;
  v_gender          text;
  v_role            text;
  v_is_owner        boolean;
  v_other_parish    uuid;
  v_other_house     uuid;
  v_other_gender    text;
  v_other_status    text;
  v_other_discipler uuid;
  v_other_approval  boolean;
  v_leader_reach    boolean;  -- may DM any active parish member, gates bypassed
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  if p_other is null or p_other = v_me then raise exception 'invalid DM target'; end if;

  select parish_id, house_id, gender, role, is_owner
    into v_parish, v_house, v_gender, v_role, v_is_owner
    from public.user_profiles where id = v_me;

  select p.parish_id, p.house_id, p.gender, p.status, p.discipler_id,
         coalesce(pv.cross_gender_dm_approval, true)
    into v_other_parish, v_other_house, v_other_gender, v_other_status,
         v_other_discipler, v_other_approval
    from public.user_profiles p
    left join public.user_privacy pv on pv.user_id = p.id
    where p.id = p_other;

  -- Same parish holds for everyone, leaders included.
  if v_other_parish is null or v_other_parish <> v_parish then
    raise exception 'DM target must be in your parish';
  end if;

  -- Existing DM between exactly these two? Return it (do not re-gate) so no one
  -- loses access to a conversation already in progress.
  select c.id into v_chat
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = v_me
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = p_other
  where c.kind = 'dm'
  limit 1;
  if v_chat is not null then
    return v_chat;
  end if;

  -- A NEW DM may only target an active member (the directory only lists active
  -- members; this keeps pending/suspended/rejected un-DMable for everyone).
  if v_other_status is distinct from 'active' then
    raise exception 'DM target is not an active member';
  end if;

  -- Leader reach (pastoral care): owner / pastor / admin may DM ANY active
  -- parish member, and a caller may DM anyone they are the assigned discipler
  -- of. All bypass the cross-house and cross-gender gates. The discipler check
  -- is the discipler_id POINTER (target.discipler_id = me), not the caller's
  -- role label -- matching is_discipler_for_subscription() (0022): the assigned
  -- mentor relationship is authoritative even if the mentor's role is 'member'.
  -- House leaders and students get no blanket reach (a house leader already
  -- shares a house with their members). coalesce + `is not distinct from` keep
  -- this strictly boolean so a null discipler_id can't leak a true through `not`.
  v_leader_reach := coalesce(
       v_is_owner
    or v_role in ('pastor', 'admin')
    or (v_other_discipler is not distinct from v_me),
    false);

  if not v_leader_reach then
    -- Finding B1 (0021): students DM house-mate to house-mate so a house leader
    -- oversees the shared house.
    if v_house is null or v_other_house is null then
      raise exception 'cross-house DM blocked: both members must belong to a house for leader oversight';
    end if;
    if v_house <> v_other_house then
      raise exception 'cross-house DM blocked: no shared house leader for oversight';
    end if;

    -- Finding B2 (0020): cross-gender DM approval gate.
    if v_gender is null or v_other_gender is null then
      raise notice 'cross-gender DM gate skipped: gender unset for % or % (legacy user)', v_me, p_other;
    elsif v_gender <> v_other_gender and v_other_approval then
      raise exception 'cross-gender DM requires recipient approval';
    end if;
  end if;

  -- Per 0029 a DM is private to its two participants; chat.house_id no longer
  -- drives DM read/post access (that is is_chat_member only). Keep house_id when
  -- both share one house (tidy grouping); leave null for cross-house leader DMs.
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
