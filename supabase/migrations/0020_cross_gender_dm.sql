-- 0020_cross_gender_dm.sql
-- Finding B2: cross-gender DM approval gate.
--
-- user_privacy.cross_gender_dm_approval (default true) and user_profiles.gender
-- already exist, but create_dm() never checked them, so the guardrail had no
-- behaviour. Mobile now collects gender in onboarding, so we can enforce it.
--
-- This redefines create_dm() (append-only; 0006 is left intact) adding the
-- cross-gender rule. The cross-house rule lands next in 0021, which redefines
-- create_dm() once more as the authoritative version.
--
-- Rules:
--   * both genders set, differ, recipient requires approval  -> block.
--   * both genders set, differ, recipient opted out          -> proceed.
--   * either gender null (legacy users)                      -> proceed + NOTICE.
-- The gate runs only when CREATING a new DM; an already-existing DM is returned
-- unchanged so no one loses access to a conversation already in progress.

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

  -- Finding B2: cross-gender DM approval gate.
  if v_gender is null or v_other_gender is null then
    raise notice 'cross-gender DM gate skipped: gender unset for % or % (legacy user)', v_me, p_other;
  elsif v_gender <> v_other_gender and v_other_approval then
    raise exception 'cross-gender DM requires recipient approval';
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
