-- 0016_campuses.sql
-- Campuses within a parish. The pilot parish (CCCFSP FUOYE) spans two physical
-- campuses, Oye (main) and Ikole. We keep ONE parish with shared houses and
-- content, and tag each member with their campus. This lets the directory,
-- analytics, and (later) campus-scoped announcements distinguish the two
-- without splitting the fellowship. Houses remain parish-wide so a house
-- fellowship stays one body across campuses.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.campuses (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  slug        text not null,
  name        text not null,
  is_primary  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (parish_id, slug)
);

create index if not exists idx_campuses_parish on public.campuses (parish_id);

-- Members carry the campus they attend (nullable until chosen in onboarding).
alter table public.user_profiles
  add column if not exists campus_id uuid references public.campuses(id) on delete set null;

create index if not exists idx_user_profiles_campus on public.user_profiles (campus_id);

-- ---------------------------------------------------------------------------
-- RLS: parish members read their parish's campuses; admins manage them.
-- ---------------------------------------------------------------------------

alter table public.campuses enable row level security;

create policy "campuses_select_parish" on public.campuses for select
  to authenticated
  using (parish_id = public.current_parish_id());

create policy "campuses_admin_write" on public.campuses for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ---------------------------------------------------------------------------
-- Seed: the two FUOYE campuses for the pilot parish. Fixed UUIDs, idempotent.
-- (Parish UUID from 0001_init_identity.sql.)
-- ---------------------------------------------------------------------------

insert into public.campuses (id, parish_id, slug, name, is_primary) values
  ('00000000-0000-0000-0000-0000000ca401', '00000000-0000-0000-0000-000000000001', 'oye',   'Oye Campus',   true),
  ('00000000-0000-0000-0000-0000000ca402', '00000000-0000-0000-0000-000000000001', 'ikole', 'Ikole Campus', false)
on conflict (parish_id, slug) do nothing;
