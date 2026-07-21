-- 0039_member_deletions.sql
-- Durable service-role audit trail for intentional account deletions. The
-- snapshot remains after the target's auth/profile row is deleted.

create table if not exists public.member_deletions (
  id               uuid primary key default gen_random_uuid(),
  parish_id        uuid not null references public.parishes(id) on delete cascade,
  actor_profile_id uuid references public.user_profiles(id) on delete set null,
  actor_name       text not null,
  target_name      text not null,
  target_email     text,
  target_role      text not null,
  deleted_at       timestamptz not null default now()
);

create index if not exists idx_member_deletions_parish_date
  on public.member_deletions (parish_id, deleted_at desc);

alter table public.member_deletions enable row level security;

drop policy if exists "member_deletions_admin_select" on public.member_deletions;
create policy "member_deletions_admin_select" on public.member_deletions for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Inserts are intentionally service-role only. Account deletion is performed
-- by the server-side admin client after its own owner/admin checks.
