-- 0009_safety.sql
-- Safety & moderation: blocks, reports, and the moderation log. Block/report/
-- mute must be one tap from any chat surface (pastoral guardrail), so the
-- tables are simple and the block actually hides content at the row level.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.blocks (
  blocker_id uuid not null references public.user_profiles(id) on delete cascade,
  blocked_id uuid not null references public.user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  reporter_id uuid not null references public.user_profiles(id) on delete cascade,
  target_type text not null check (target_type in ('message', 'user', 'prayer_request', 'ask_question')),
  target_id   uuid not null,
  reason      text,
  status      text not null default 'open'
                check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  resolved_by uuid references public.user_profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- Written by the moderate-message edge function (service role); read by admins.
create table if not exists public.moderation_log (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid references public.messages(id) on delete set null,
  flag         text not null,                 -- e.g. 'harassment', 'self-harm'
  severity     text not null default 'low'
                 check (severity in ('low', 'medium', 'high')),
  action_taken text not null default 'logged'
                 check (action_taken in ('logged', 'soft_deleted', 'escalated')),
  created_at   timestamptz not null default now()
);

create index if not exists idx_blocks_blocker on public.blocks (blocker_id);
create index if not exists idx_reports_parish_status on public.reports (parish_id, status, created_at desc);
create index if not exists idx_moderation_log_message on public.moderation_log (message_id);

-- ---------------------------------------------------------------------------
-- Block helper
-- ---------------------------------------------------------------------------

create or replace function public.is_blocked_by_me(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks b
    where b.blocker_id = public.current_profile_id() and b.blocked_id = p_target
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.blocks         enable row level security;
alter table public.reports        enable row level security;
alter table public.moderation_log enable row level security;

-- Blocks: you manage your own block list.
create policy "blocks_own" on public.blocks for all
  to authenticated
  using (blocker_id = public.current_profile_id())
  with check (blocker_id = public.current_profile_id());

-- Reports: file your own; see your own; admins see + resolve their parish's.
create policy "reports_insert_own" on public.reports for insert
  to authenticated
  with check (reporter_id = public.current_profile_id() and parish_id = public.current_parish_id());

create policy "reports_select_own" on public.reports for select
  to authenticated
  using (reporter_id = public.current_profile_id());

create policy "reports_select_admin" on public.reports for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

create policy "reports_update_admin" on public.reports for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Moderation log: parish admins read; only the service role writes.
create policy "moderation_log_select_admin" on public.moderation_log for select
  to authenticated
  using (public.is_parish_admin());

-- ---------------------------------------------------------------------------
-- Blocking hides content: a RESTRICTIVE policy AND-ed with the permissive
-- message policies so a blocker never sees a blocked user's messages.
-- ---------------------------------------------------------------------------

create policy "messages_hide_blocked" on public.messages as restrictive for select
  to authenticated
  using (author_id is null or not public.is_blocked_by_me(author_id));
