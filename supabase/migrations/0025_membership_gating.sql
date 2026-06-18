-- 0025_membership_gating.sql
-- School-email gating for student onboarding, with an approval fallback, plus
-- admin-elevated leaders. Pilot: one parish, campuses Oye/Ikole (FUOYE).
--
-- SECURITY MODEL (the heart of this migration):
--   * A new signup is auto-APPROVED only if its email domain matches a campus's
--     allowlist (then campus + parish are derived, status='active'); otherwise
--     status='pending' with NO parish/campus until an admin approves.
--   * Role ALWAYS defaults to 'member'. handle_new_user never reads role/status
--     from signup metadata.
--   * A user can NEVER change their own role / status / parish_id / campus_id.
--     Enforced by a column-guard trigger (defence beyond RLS). Only parish
--     admins, or privileged DB roles (the SECURITY DEFINER RPCs / service role),
--     may change those columns.
--   * Pending/suspended/rejected members are walled off: pending users have a
--     null parish (so parish-scoped content/chats return nothing), and the
--     directory + chat helpers additionally require the viewer to be active and
--     hide non-active members.

-- ---------------------------------------------------------------------------
-- 1. Per-campus domain allowlist (lowercase, no '@').
-- ---------------------------------------------------------------------------

alter table public.campuses
  add column if not exists allowed_email_domains text[] not null default '{}';

-- Seed real FUOYE domains here once confirmed, e.g.:
--   update public.campuses set allowed_email_domains = array['fuoye.edu.ng','students.fuoye.edu.ng']
--   where parish_id = '00000000-0000-0000-0000-000000000001';
-- Until seeded, every signup falls through to 'pending' (approval fallback).

-- ---------------------------------------------------------------------------
-- 2. Membership status. Existing profiles backfilled to 'active'.
-- ---------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists status text not null default 'pending'
    check (status in ('pending','active','rejected','suspended'));

update public.user_profiles set status = 'active' where status <> 'active';

create index if not exists idx_user_profiles_status on public.user_profiles (parish_id, status);

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_active_member()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'active' from public.user_profiles where auth_id = auth.uid()), false);
$$;

-- ---------------------------------------------------------------------------
-- 4. Self-escalation guard: block changes to protected columns unless the actor
--    is a parish admin or a privileged DB role (postgres/service_role, i.e. the
--    SECURITY DEFINER RPCs and the auth trigger). NOT security definer, so
--    current_user reflects the real caller.
-- ---------------------------------------------------------------------------

create or replace function public.guard_profile_protected_cols()
returns trigger language plpgsql as $$
begin
  if (new.role       is distinct from old.role)
     or (new.status    is distinct from old.status)
     or (new.parish_id is distinct from old.parish_id)
     or (new.campus_id is distinct from old.campus_id) then
    if current_user in ('authenticated', 'anon') and not public.is_parish_admin() then
      raise exception 'permission denied: role/status/parish_id/campus_id are not user-editable';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_profile_cols on public.user_profiles;
create trigger trg_guard_profile_cols
  before update on public.user_profiles
  for each row execute function public.guard_profile_protected_cols();

-- ---------------------------------------------------------------------------
-- 5. Signup: auto-approve + auto-assign campus by email domain.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_domain      text;
  v_match_count int;
  v_campus      uuid;
  v_parish      uuid;
  v_status      text;
  v_profile_id  uuid;
begin
  v_domain := lower(split_part(coalesce(new.email, ''), '@', 2));

  -- Campuses whose allowlist contains the domain (pilot: within the one parish).
  select count(*) into v_match_count
    from public.campuses c
    where v_domain <> '' and v_domain = any (c.allowed_email_domains);

  if v_match_count = 1 then
    -- Exactly one campus matches: derive both campus and parish.
    select c.id, c.parish_id into v_campus, v_parish
      from public.campuses c
      where v_domain = any (c.allowed_email_domains)
      limit 1;
    v_status := 'active';
  elsif v_match_count > 1 then
    -- Several campuses share the domain (e.g. one FUOYE domain across Oye +
    -- Ikole): activate into the parish, campus null (member picks in onboarding).
    select c.parish_id into v_parish
      from public.campuses c
      where v_domain = any (c.allowed_email_domains)
      limit 1;
    v_campus := null;
    v_status := 'active';
  else
    v_status := 'pending';
    v_campus := null;
    v_parish := null;
  end if;

  insert into public.user_profiles (auth_id, parish_id, campus_id, name, role, status)
  values (
    new.id, v_parish, v_campus,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)),
    'member',          -- role is ALWAYS member; never from metadata
    v_status
  )
  returning id into v_profile_id;

  insert into public.user_privacy (user_id) values (v_profile_id);
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Admin approval RPCs (parish admins only).
-- ---------------------------------------------------------------------------

create or replace function public.approve_member(p_user uuid, p_campus uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_parish uuid;
begin
  if not public.is_parish_admin() then raise exception 'not authorized'; end if;
  select parish_id into v_parish from public.campuses where id = p_campus;
  if v_parish is null then raise exception 'campus not found'; end if;
  if v_parish <> public.current_parish_id() then raise exception 'campus is not in your parish'; end if;
  update public.user_profiles
    set status = 'active', campus_id = p_campus, parish_id = v_parish
    where id = p_user;
end $$;

create or replace function public.reject_member(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_parish_admin() then raise exception 'not authorized'; end if;
  update public.user_profiles
    set status = 'rejected'
    where id = p_user
      and (parish_id = public.current_parish_id() or parish_id is null);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Defence-in-depth reads: hide non-active members; gate chat on active.
-- ---------------------------------------------------------------------------

-- Directory: you always see yourself; you see parish-mates only if both you and
-- they are active. Pending/suspended/rejected members are hidden from others.
drop policy if exists "user_profiles_select_same_parish" on public.user_profiles;
create policy "user_profiles_select_same_parish" on public.user_profiles for select
  to authenticated
  using (
    auth_id = auth.uid()
    or (parish_id = public.current_parish_id() and status = 'active' and public.is_active_member())
  );

-- Chat read/post require an active viewer (re-declared from 0017 + active gate).
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
      or (c.kind = 'dm' and c.house_id is not null
          and public.current_profile_id() = (select h.leader_id from public.houses h where h.id = c.house_id))
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
      or (c.kind = 'house_group' and c.house_id = public.current_house_id())
      or (c.kind in ('dm', 'discipler', 'ask_pastor_thread') and public.is_chat_member(p_chat))
    )
  );
$$;
