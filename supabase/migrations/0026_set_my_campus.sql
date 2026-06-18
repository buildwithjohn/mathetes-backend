-- 0026_set_my_campus.sql
-- Onboarding fix for the membership gating (0025): a FUOYE school-email signup
-- is auto-activated with campus_id = NULL (both campuses share the domain) and
-- must pick Oye/Ikole. But the guard trigger locks campus_id against client
-- writes. This RPC is the one sanctioned path: a member sets their OWN campus
-- ONCE, and only to a campus in their own parish. (house_id stays directly
-- editable as before; only campus_id needed this.)

create or replace function public.set_my_campus(p_campus uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me      uuid := public.current_profile_id();
  v_parish  uuid;
  v_current uuid;
  v_campus_parish uuid;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;

  select parish_id, campus_id into v_parish, v_current
    from public.user_profiles where id = v_me;

  -- Set once: don't allow changing an already-chosen campus.
  if v_current is not null then raise exception 'campus already set'; end if;

  select parish_id into v_campus_parish from public.campuses where id = p_campus;
  if v_campus_parish is null then raise exception 'campus not found'; end if;
  if v_parish is null or v_campus_parish <> v_parish then
    raise exception 'campus is not in your parish';
  end if;

  update public.user_profiles set campus_id = p_campus where id = v_me;
end $$;
