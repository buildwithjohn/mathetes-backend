-- 0027_oversight.sql
-- Backend support for the mobile leader "Oversight" tab (Phase 2: approvals +
-- reports). Additive only — does NOT widen DM-content access (the existence-vs-
-- content question for house-leader DM oversight is handled separately).

-- ---------------------------------------------------------------------------
-- 1. Approvals: parish admins can SEE pending signups (otherwise walled off).
--    Pending users have a null parish, so we can't scope by parish — in the
--    single-parish pilot every pending signup is a candidate for the parish.
--    (Approvals stay pastor/admin only via is_parish_admin(); house leaders do
--    not get this.)
-- ---------------------------------------------------------------------------

drop policy if exists "user_profiles_admin_pending_select" on public.user_profiles;
create policy "user_profiles_admin_pending_select" on public.user_profiles for select
  to authenticated
  using (public.is_parish_admin() and status = 'pending');

-- Pending queue with email (auth.users isn't client-readable) for the approve UI.
create or replace function public.list_pending_members()
returns table (id uuid, name text, email text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_parish_admin() then raise exception 'not authorized'; end if;
  return query
    select p.id, p.name, u.email, p.joined_at
    from public.user_profiles p
    join auth.users u on u.id = p.auth_id
    where p.status = 'pending'
    order by p.joined_at;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Reports: parish admins already SELECT + UPDATE parish reports (0009).
--    Add a clean resolve/dismiss RPC that stamps resolver + timestamp.
--    (House-leader-scoped report reads are deferred — a report has no house_id;
--    attributing one to a house needs target-type-specific joins. For now the
--    reports inbox is pastor/admin, parish-scoped.)
-- ---------------------------------------------------------------------------

create or replace function public.resolve_report(p_report uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_parish_admin() then raise exception 'not authorized'; end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'status must be reviewing|resolved|dismissed';
  end if;
  update public.reports
    set status = p_status,
        resolved_by = public.current_profile_id(),
        resolved_at = case when p_status in ('resolved','dismissed') then now() else null end
    where id = p_report and parish_id = public.current_parish_id();
end $$;
