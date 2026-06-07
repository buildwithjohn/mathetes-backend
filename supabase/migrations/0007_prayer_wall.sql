-- 0007_prayer_wall.sql
-- Prayer wall: requests (house-scoped or parish-wide), "I prayed" taps, and
-- reactions. House leaders see every request in their house for pastoral care,
-- including anonymous ones (the anonymous flag hides identity in the UI, not
-- from the leader's duty of care).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.prayer_requests (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  house_id    uuid references public.houses(id) on delete set null,  -- null => parish-wide
  author_id   uuid not null references public.user_profiles(id) on delete cascade,
  body        text not null,
  anonymous   boolean not null default false,
  urgent      boolean not null default false,
  praise      boolean not null default false,   -- praise report vs request
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists public.prayer_pray (
  request_id uuid not null references public.prayer_requests(id) on delete cascade,
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

create table if not exists public.prayer_reactions (
  request_id uuid not null references public.prayer_requests(id) on delete cascade,
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  emoji      text not null check (emoji in ('🙏', '❤️', 'amen', '🔥', '✋')),
  created_at timestamptz not null default now(),
  primary key (request_id, user_id, emoji)
);

create index if not exists idx_prayer_requests_scope on public.prayer_requests (parish_id, house_id, created_at desc);
create index if not exists idx_prayer_pray_request on public.prayer_pray (request_id);
create index if not exists idx_prayer_reactions_request on public.prayer_reactions (request_id);

-- ---------------------------------------------------------------------------
-- Visibility helper (SECURITY DEFINER): can the caller see this request?
-- ---------------------------------------------------------------------------

create or replace function public.can_read_prayer(p_request uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.prayer_requests r
    where r.id = p_request
      and r.parish_id = public.current_parish_id()
      and (
           r.house_id is null                                   -- parish-wide
        or r.house_id = public.current_house_id()               -- your house
        or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = r.house_id)
        or public.is_parish_admin()
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.prayer_requests  enable row level security;
alter table public.prayer_pray      enable row level security;
alter table public.prayer_reactions enable row level security;

-- Read: parish-wide requests to all parish members; house requests to that
-- house (members + leader), plus parish admins.
create policy "prayer_requests_select" on public.prayer_requests for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
         house_id is null
      or house_id = public.current_house_id()
      or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
      or public.is_parish_admin()
    )
  );

-- Insert: your own request, in your parish, scoped to your house or parish-wide.
create policy "prayer_requests_insert_own" on public.prayer_requests for insert
  to authenticated
  with check (
    author_id = public.current_profile_id()
    and parish_id = public.current_parish_id()
    and (house_id is null or house_id = public.current_house_id())
  );

-- Update (archive / edit): author, the house leader, or a parish admin.
create policy "prayer_requests_update" on public.prayer_requests for update
  to authenticated
  using (
    author_id = public.current_profile_id()
    or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
    or public.is_parish_admin()
  )
  with check (
    author_id = public.current_profile_id()
    or public.current_profile_id() = (select h.leader_id from public.houses h where h.id = prayer_requests.house_id)
    or public.is_parish_admin()
  );

-- Author may delete their own request.
create policy "prayer_requests_delete_own" on public.prayer_requests for delete
  to authenticated
  using (author_id = public.current_profile_id());

-- prayer_pray: see taps on visible requests; record/remove your own tap.
create policy "prayer_pray_select" on public.prayer_pray for select
  to authenticated using (public.can_read_prayer(request_id));

create policy "prayer_pray_insert_own" on public.prayer_pray for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_prayer(request_id));

create policy "prayer_pray_delete_own" on public.prayer_pray for delete
  to authenticated using (user_id = public.current_profile_id());

-- prayer_reactions: same model as taps.
create policy "prayer_reactions_select" on public.prayer_reactions for select
  to authenticated using (public.can_read_prayer(request_id));

create policy "prayer_reactions_insert_own" on public.prayer_reactions for insert
  to authenticated
  with check (user_id = public.current_profile_id() and public.can_read_prayer(request_id));

create policy "prayer_reactions_delete_own" on public.prayer_reactions for delete
  to authenticated using (user_id = public.current_profile_id());
