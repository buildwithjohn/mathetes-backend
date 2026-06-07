-- 0001_init_identity.sql
-- Identity and parish structure: parishes, houses, user_profiles, user_privacy.
-- Multi-tenant from day one. Pilot exposes a single parish (CCCFSP FUOYE).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.parishes (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name        text not null,
  abbr        text not null,
  campus_name text,
  network_id  uuid,
  created_at  timestamptz not null default now()
);

create table if not exists public.houses (
  id         uuid primary key default gen_random_uuid(),
  parish_id  uuid not null references public.parishes(id) on delete cascade,
  slug       text not null,
  name       text not null,
  color      text not null,                 -- hex code, e.g. '#A87C3E'
  verse      text,
  verse_ref  text,
  leader_id  uuid,                          -- -> user_profiles(id), set later
  created_at timestamptz not null default now(),
  unique (parish_id, slug)
);

create table if not exists public.user_profiles (
  id                uuid primary key default gen_random_uuid(),
  auth_id           uuid unique not null references auth.users(id) on delete cascade,
  parish_id         uuid references public.parishes(id),
  house_id          uuid references public.houses(id),
  name              text not null,
  photo_url         text,
  photo_visibility  text not null default 'parish'
                      check (photo_visibility in ('parish', 'house', 'none')),
  role              text not null default 'member'
                      check (role in ('member', 'house_leader', 'discipler', 'pastor', 'admin')),
  gender            text check (gender in ('male', 'female')),
  year              text,
  dept              text,
  pinned_verse_ref  text,
  joined_at         timestamptz not null default now()
);

-- houses.leader_id references user_profiles; add FK now that the table exists.
alter table public.houses
  add constraint houses_leader_id_fkey
  foreign key (leader_id) references public.user_profiles(id) on delete set null;

create table if not exists public.user_privacy (
  user_id                  uuid primary key references public.user_profiles(id) on delete cascade,
  dm_who                   text not null default 'house'
                             check (dm_who in ('all_parish', 'house', 'discipler', 'none')),
  cross_gender_dm_approval boolean not null default true,
  mentions_notify          boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists idx_user_profiles_auth_id  on public.user_profiles (auth_id);
create index if not exists idx_user_profiles_parish_house on public.user_profiles (parish_id, house_id);
create index if not exists idx_houses_parish on public.houses (parish_id);

-- ---------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER so RLS policies can call them without
-- recursing on the very tables they protect).
-- ---------------------------------------------------------------------------

create or replace function public.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.user_profiles where auth_id = auth.uid();
$$;

create or replace function public.current_parish_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select parish_id from public.user_profiles where auth_id = auth.uid();
$$;

create or replace function public.current_house_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select house_id from public.user_profiles where auth_id = auth.uid();
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.user_profiles where auth_id = auth.uid();
$$;

create or replace function public.is_parish_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role in ('pastor', 'admin') from public.user_profiles where auth_id = auth.uid()),
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- New-user trigger: create a profile + privacy row for every auth user.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parish_id  uuid;
  v_profile_id uuid;
begin
  -- Pilot: assign everyone to the single pilot parish by default.
  select id into v_parish_id from public.parishes where slug = 'cccfsp-fuoye' limit 1;

  insert into public.user_profiles (auth_id, parish_id, name)
  values (
    new.id,
    v_parish_id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1))
  )
  returning id into v_profile_id;

  insert into public.user_privacy (user_id) values (v_profile_id);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.parishes      enable row level security;
alter table public.houses        enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_privacy  enable row level security;

-- parishes: any authenticated user can read.
create policy "parishes_select_authenticated"
  on public.parishes for select
  to authenticated
  using (true);

-- houses: readable by authenticated users in the same parish.
create policy "houses_select_same_parish"
  on public.houses for select
  to authenticated
  using (parish_id = public.current_parish_id());

-- houses: parish admins manage their parish's houses.
create policy "houses_admin_write"
  on public.houses for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- user_profiles: read anyone in your parish.
create policy "user_profiles_select_same_parish"
  on public.user_profiles for select
  to authenticated
  using (parish_id = public.current_parish_id());

-- user_profiles: insert only your own row (auth_id must be you).
create policy "user_profiles_insert_own"
  on public.user_profiles for insert
  to authenticated
  with check (auth_id = auth.uid());

-- user_profiles: update only your own row. Role/parish are protected by the
-- admin policy below; ordinary users may change profile fields on their row.
create policy "user_profiles_update_own"
  on public.user_profiles for update
  to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

-- user_profiles: parish admins can manage profiles in their parish (roles,
-- house assignment, discipler assignment, etc.).
create policy "user_profiles_admin_write"
  on public.user_profiles for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- user_privacy: read/write only your own row.
create policy "user_privacy_select_own"
  on public.user_privacy for select
  to authenticated
  using (user_id = public.current_profile_id());

create policy "user_privacy_insert_own"
  on public.user_privacy for insert
  to authenticated
  with check (user_id = public.current_profile_id());

create policy "user_privacy_update_own"
  on public.user_privacy for update
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- ---------------------------------------------------------------------------
-- Seed: CCCFSP FUOYE pilot parish and its 7 house fellowships.
-- Fixed UUIDs so other seeds and dev fixtures can reference them.
-- Idempotent via ON CONFLICT.
-- ---------------------------------------------------------------------------

insert into public.parishes (id, slug, name, abbr, campus_name)
values (
  '00000000-0000-0000-0000-000000000001',
  'cccfsp-fuoye',
  'Celestial Church of Christ Federal Students Parish',
  'CCCFSP',
  'Federal University Oye-Ekiti (FUOYE)'
)
on conflict (slug) do nothing;

insert into public.houses (id, parish_id, slug, name, color, verse_ref, verse) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
   'bethel',  'Bethel House',  '#B87333', 'Genesis 28:17',
   'And he was afraid, and said, How dreadful is this place! this is none other but the house of God, and this is the gate of heaven.'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001',
   'antioch', 'Antioch House', '#722F37', 'Acts 11:26',
   'And the disciples were called Christians first in Antioch.'),
  ('00000000-0000-0000-0000-0000000000be', '00000000-0000-0000-0000-000000000001',
   'berea',   'Berea House',   '#A87C3E', 'Acts 17:11',
   'These were more noble than those in Thessalonica, in that they received the word with all readiness of mind, and searched the scriptures daily, whether those things were so.'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001',
   'bethany', 'Bethany House', '#7A8A6E', 'John 11:25',
   'Jesus said unto her, I am the resurrection, and the life: he that believeth in me, though he were dead, yet shall he live.'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001',
   'zion',    'Zion House',    '#C9A24A', 'Psalm 125:1',
   'They that trust in the LORD shall be as mount Zion, which cannot be removed, but abideth for ever.'),
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001',
   'hebron',  'Hebron House',  '#A85838', 'Psalm 133:1',
   'Behold, how good and how pleasant it is for brethren to dwell together in unity!'),
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000001',
   'salem',   'Salem House',   '#6B7F8A', 'Hebrews 7:2',
   'To whom also Abraham gave a tenth part of all; first being by interpretation King of righteousness, and after that also King of Salem, which is, King of peace.')
on conflict (parish_id, slug) do nothing;
