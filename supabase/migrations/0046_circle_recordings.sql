-- 0046_circle_recordings.sql
--
-- Host-controlled recordings for Circle teachings and sermons. Media stays in
-- the private R2 bucket; the database stores only audit/status metadata. A
-- server-only Edge Function starts/stops LiveKit Egress and grants short-lived
-- downloads after it re-checks Circle membership.

create table if not exists public.circle_recordings (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.circle_meetings(id) on delete cascade,
  chat_id uuid not null references public.chats(id) on delete cascade,
  parish_id uuid not null references public.parishes(id) on delete cascade,
  created_by uuid references public.user_profiles(id) on delete set null,
  title text not null,
  media_kind text not null check (media_kind in ('audio', 'video')),
  status text not null default 'recording'
    check (status in ('recording', 'processing', 'ready', 'failed', 'deleted')),
  egress_id text not null unique,
  storage_key text not null,
  duration_seconds integer,
  size_bytes bigint,
  failure_reason text,
  started_at timestamptz not null default now(),
  stopped_at timestamptz,
  ready_at timestamptz,
  deleted_at timestamptz
);

create index if not exists idx_circle_recordings_meeting_status
  on public.circle_recordings (meeting_id, status, started_at desc);
create index if not exists idx_circle_recordings_chat_ready
  on public.circle_recordings (chat_id, ready_at desc) where status = 'ready';
-- A double tap or two admins must never start two billable egress jobs for one
-- meeting. Finished/failed recordings remain historical entries.
create unique index if not exists idx_circle_recordings_one_active_per_meeting
  on public.circle_recordings (meeting_id)
  where status in ('recording', 'processing');

alter table public.circle_recordings enable row level security;

drop policy if exists "circle recordings visible to members" on public.circle_recordings;
create policy "circle recordings visible to members" on public.circle_recordings for select to authenticated
  using (
    public.is_active_member()
    and parish_id = public.current_parish_id()
    and public.is_chat_member(chat_id)
    and status <> 'deleted'
  );

-- Only service-role Edge Functions write recording state. It prevents a client
-- from asserting that an unrecorded call has a file or inventing another
-- Circle's R2 key.

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'circle_recordings'
  ) then
    alter publication supabase_realtime add table public.circle_recordings;
  end if;
exception when others then
  raise notice 'realtime: could not add circle_recordings: %', sqlerrm;
end $$;
