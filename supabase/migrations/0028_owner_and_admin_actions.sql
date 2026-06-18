-- 0028_owner_and_admin_actions.sql
-- Formalize the owner concept (already added on prod via SQL) and tighten the
-- management surface per the admin team:
--   * user_profiles.is_owner — owner = role 'admin' AND is_owner = true. No new
--     enum role.
--   * approve_member / reject_member / resolve_report require role = 'admin'
--     (includes owners); pastors lose these actions. answer_question stays
--     pastor+admin.
--   * answer_question is re-answer-safe (only an 'awaiting' question can be
--     answered), so a stale submit can't clobber an answer made on another surface.
--   * Self-escalation guard kept and extended: is_owner is now a protected column,
--     and granting/removing the admin role or ownership requires an owner.

-- ---------------------------------------------------------------------------
-- 1. Owner column (idempotent; already present on prod).
-- ---------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists is_owner boolean not null default false;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'admin' and is_owner from public.user_profiles where auth_id = auth.uid()),
    false);
$$;

-- ---------------------------------------------------------------------------
-- 2. Self-escalation guard: protect is_owner too, and require an owner to
--    grant/remove the admin role or ownership.
-- ---------------------------------------------------------------------------

create or replace function public.guard_profile_protected_cols()
returns trigger language plpgsql as $$
begin
  if (new.role       is distinct from old.role)
     or (new.status    is distinct from old.status)
     or (new.parish_id is distinct from old.parish_id)
     or (new.campus_id is distinct from old.campus_id)
     or (new.is_owner  is distinct from old.is_owner) then

    if current_user in ('authenticated', 'anon') then
      if not public.is_parish_admin() then
        raise exception 'permission denied: role/status/parish_id/campus_id/is_owner are not user-editable';
      end if;
      -- Only an owner may grant or remove the admin role, or change ownership.
      if ((new.role is distinct from old.role) and ('admin' = new.role or 'admin' = old.role))
         or (new.is_owner is distinct from old.is_owner) then
        if not public.is_owner() then
          raise exception 'only an owner can grant/remove the admin role or ownership';
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Management actions: admin-only (pastors lose these).
-- ---------------------------------------------------------------------------

create or replace function public.approve_member(p_user uuid, p_campus uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_parish uuid;
begin
  if public.current_user_role() <> 'admin' then raise exception 'not authorized'; end if;
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
  if public.current_user_role() <> 'admin' then raise exception 'not authorized'; end if;
  update public.user_profiles
    set status = 'rejected'
    where id = p_user
      and (parish_id = public.current_parish_id() or parish_id is null);
end $$;

create or replace function public.resolve_report(p_report uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.current_user_role() <> 'admin' then raise exception 'not authorized'; end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'status must be reviewing|resolved|dismissed';
  end if;
  update public.reports
    set status = p_status,
        resolved_by = public.current_profile_id(),
        resolved_at = case when p_status in ('resolved','dismissed') then now() else null end
    where id = p_report and parish_id = public.current_parish_id();
end $$;

-- ---------------------------------------------------------------------------
-- 4. answer_question: pastor+admin, but re-answer-safe. Only an 'awaiting'
--    question can be answered, so a stale submit can't overwrite an answer
--    already given on another surface.
-- ---------------------------------------------------------------------------

create or replace function public.answer_question(
  p_id text,
  p_response text,
  p_public boolean default false
)
returns public.ask_questions
language plpgsql security definer set search_path = public as $$
declare q public.ask_questions;
begin
  if not public.is_parish_admin() then
    raise exception 'only pastor/admin may answer questions';
  end if;

  update public.ask_questions
    set response_body = p_response,
        privacy       = case when p_public then 'public' else 'private' end,
        status        = 'answered',
        answered_by   = public.current_profile_id(),
        answered_at   = now()
    where id = p_id::uuid
      and parish_id = public.current_parish_id()
      and status = 'awaiting'         -- re-answer guard
    returning * into q;

  if q.id is null then
    raise exception 'question not found in your parish, or it was already answered';
  end if;
  return q;
end;
$$;
