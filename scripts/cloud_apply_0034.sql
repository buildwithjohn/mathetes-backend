-- cloud_apply_0034.sql
-- Idempotent bundle of migration 0034 (fully open DMs) for the hosted DB.
-- Paste into the Supabase SQL Editor and Run. Safe to re-run.
--
-- Makes create_dm fully open: any active parish member may DM any other active
-- parish member. Removes the cross-house (B1) and cross-gender-approval (B2)
-- gates. Kept: same parish + active target. Private-DM oversight is unchanged
-- (0029). Prerequisites (already live): 0001, 0006, 0025 (status/is_active).

do $preflight$
begin
  if to_regprocedure('public.current_profile_id()') is null then
    raise exception 'cloud_apply_0034: current_profile_id() missing -- apply migration 0001 first';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='user_profiles' and column_name='status') then
    raise exception 'cloud_apply_0034: user_profiles.status missing -- apply migration 0025 first';
  end if;
end $preflight$;

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

  if v_other_parish is null or v_other_parish <> v_parish then
    raise exception 'DM target must be in your parish';
  end if;

  select c.id into v_chat
  from public.chats c
  join public.chat_members m1 on m1.chat_id = c.id and m1.user_id = v_me
  join public.chat_members m2 on m2.chat_id = c.id and m2.user_id = p_other
  where c.kind = 'dm'
  limit 1;
  if v_chat is not null then
    return v_chat;
  end if;

  if v_other_status is distinct from 'active' then
    raise exception 'DM target is not an active member';
  end if;

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

-- verification (read-only): confirms the function exists with the expected arg.
select 'create_dm' as check, pg_get_function_identity_arguments(oid) as args
  from pg_proc where proname = 'create_dm' and pronamespace = 'public'::regnamespace;
