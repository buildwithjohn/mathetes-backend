-- 0021_cross_house_dm.sql
-- Finding B1: cross-house DM oversight policy.
--
-- CHOSEN POLICY: Option A (pilot) -- block DMs that cannot be overseen.
--
-- Background: create_dm() set chat.house_id only when both members shared a
-- house; cross-house (and house-less) DMs got NULL house_id, and can_read_chat()
-- only grants DM oversight to "the house leader of chat.house_id". A NULL there
-- means NO house leader can see the DM exists -> private messaging with no
-- accountability, which violates the pastoral guardrail.
--
-- The PM's Option A blocks only the both-houses-set-and-differ case. That still
-- leaves house-less users (NULL house_id) able to open un-overseen DMs. To honor
-- the guardrail fully, this goes one step further: a DM is allowed ONLY between
-- members of the SAME, NON-NULL house. That guarantees every DM has a house
-- leader for oversight, and matches the conservative default (user_privacy.
-- dm_who = 'house', i.e. house-mates only). Cross-campus DMs are inherently
-- cross-house under 0018 and are likewise blocked at this stage.
--
-- Post-pilot (Option B) could allow cross-house DMs by assigning oversight to
-- the parish pastor on NULL-house DMs; deferred deliberately for the pilot.
--
-- This redefines create_dm() as the AUTHORITATIVE version: it keeps the B2
-- cross-gender gate from 0020 and adds the B1 house gate (append-only; 0006 and
-- 0020 are left intact). Note: pre-existing NULL-house DM rows are not migrated
-- here; they are a data-cleanup concern and are reported separately.

create or replace function public.create_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me             uuid := public.current_profile_id();
  v_chat           uuid;
  v_parish         uuid;
  v_house          uuid;
  v_gender         text;
  v_other_parish   uuid;
  v_other_house    uuid;
  v_other_gender   text;
  v_other_approval boolean;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  if p_other is null or p_other = v_me then raise exception 'invalid DM target'; end if;

  select parish_id, house_id, gender
    into v_parish, v_house, v_gender
    from public.user_profiles where id = v_me;

  select p.parish_id, p.house_id, p.gender, coalesce(pv.cross_gender_dm_approval, true)
    into v_other_parish, v_other_house, v_other_gender, v_other_approval
    from public.user_profiles p
    left join public.user_privacy pv on pv.user_id = p.id
    where p.id = p_other;

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

  -- Finding B1: DMs must be house-mate to house-mate so a house leader oversees.
  if v_house is null or v_other_house is null then
    raise exception 'cross-house DM blocked: both members must belong to a house for leader oversight';
  end if;
  if v_house <> v_other_house then
    raise exception 'cross-house DM blocked: no shared house leader for oversight';
  end if;

  -- Finding B2: cross-gender DM approval gate.
  if v_gender is null or v_other_gender is null then
    raise notice 'cross-gender DM gate skipped: gender unset for % or % (legacy user)', v_me, p_other;
  elsif v_gender <> v_other_gender and v_other_approval then
    raise exception 'cross-gender DM requires recipient approval';
  end if;

  -- house_id is now guaranteed non-null and shared, so oversight always applies.
  insert into public.chats (kind, parish_id, house_id, created_by)
    values ('dm', v_parish, v_house, v_me)
    returning id into v_chat;

  insert into public.chat_members (chat_id, user_id, role) values
    (v_chat, v_me, 'member'),
    (v_chat, p_other, 'member')
  on conflict do nothing;

  return v_chat;
end;
$$;
