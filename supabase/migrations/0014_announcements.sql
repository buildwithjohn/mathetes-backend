-- 0014_announcements.sql
-- Parish announcements as a content table (authored from the admin dashboard).
-- The canonical schema (CLAUDE.md) lists announcements as content alongside
-- devotionals / word_of_day; the admin app writes to this table. (The chat
-- 'announcements' channel from 0006 remains for the in-app read feed; a trigger
-- here mirrors a published announcement into per-member notifications.)

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  parish_id    uuid not null references public.parishes(id) on delete cascade,
  title        text not null,
  body_md      text not null default '',
  event_data   jsonb,                              -- { date, time, location }
  banner       text check (banner in ('event', 'urgent')),
  photos       text[] not null default '{}',
  status       text not null default 'draft'
                 check (status in ('draft', 'scheduled', 'published')),
  publish_date date,
  posted_at    timestamptz,
  posted_by    uuid references public.user_profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_announcements_parish_status_date
  on public.announcements (parish_id, status, publish_date desc);

-- ---------------------------------------------------------------------------
-- RLS: parish members read published (dated today or earlier); pastor/admin
-- manage and see drafts/scheduled. Mirrors the devotionals / word_of_day model.
-- ---------------------------------------------------------------------------

alter table public.announcements enable row level security;

create policy "announcements_select_published" on public.announcements for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status = 'published' and (publish_date is null or publish_date <= current_date))
      or public.is_parish_admin()
    )
  );

create policy "announcements_admin_write" on public.announcements for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ---------------------------------------------------------------------------
-- Notify the parish when an announcement is published (transition to
-- 'published'). Reuses the notifications table from 0010. Author is skipped and
-- members are not re-notified for the same announcement.
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_announcement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published'
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'announcement', coalesce(nullif(new.title, ''), 'Parish announcement'),
           left(new.body_md, 140), new.id, 'mathetes://announcements/' || new.id
    from public.user_profiles p
    where p.parish_id = new.parish_id
      and p.id is distinct from new.posted_by
      and not exists (
        select 1 from public.notifications n
        where n.type = 'announcement' and n.target_id = new.id and n.user_id = p.id
      )
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = 'announcement' and np.channel = 'in_app' and np.enabled = false
      );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_announcement on public.announcements;
create trigger trg_notify_on_announcement
  after insert or update of status on public.announcements
  for each row execute function public.notify_on_announcement();
