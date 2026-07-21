-- 0035_content_reliability.sql
-- Make scheduled content resilient to a missed cron and persist devotional saves.

-- Due scheduled content is safe to read. The publisher still changes its status
-- and sends notifications, but content availability no longer depends on cron.
-- Repair anything already missed before installing the fallback. This also
-- restores it for older mobile builds that still filter on published only.
update public.devotionals
set status = 'published'
where status = 'scheduled' and publish_date <= current_date;

update public.word_of_day
set status = 'published'
where status = 'scheduled' and publish_date <= current_date;

drop policy if exists "devotionals_select_published" on public.devotionals;
create policy "devotionals_select_due"
  on public.devotionals for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status in ('published', 'scheduled') and publish_date <= current_date)
      or public.is_parish_admin()
    )
  );

drop policy if exists "word_of_day_select_published" on public.word_of_day;
create policy "word_of_day_select_due"
  on public.word_of_day for select
  to authenticated
  using (
    parish_id = public.current_parish_id()
    and (
      (status in ('published', 'scheduled') and publish_date <= current_date)
      or public.is_parish_admin()
    )
  );

create or replace view public.todays_word_of_day
with (security_invoker = true) as
  select * from public.word_of_day
  where status in ('published', 'scheduled') and publish_date = current_date;

create or replace view public.todays_devotional
with (security_invoker = true) as
  select * from public.devotionals
  where status in ('published', 'scheduled') and publish_date = current_date;

-- If an admin schedules content for today or an earlier date, publish it in the
-- same transaction instead of waiting for the next scheduled job.
create or replace function public.publish_due_content_on_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'scheduled'
     and new.publish_date is not null
     and new.publish_date <= current_date then
    new.status := 'published';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_devotionals_publish_due on public.devotionals;
create trigger trg_devotionals_publish_due
  before insert or update of status, publish_date on public.devotionals
  for each row execute function public.publish_due_content_on_write();

drop trigger if exists trg_word_of_day_publish_due on public.word_of_day;
create trigger trg_word_of_day_publish_due
  before insert or update of status, publish_date on public.word_of_day
  for each row execute function public.publish_due_content_on_write();

create table if not exists public.devotional_bookmarks (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.user_profiles(id) on delete cascade,
  devotional_id  uuid not null references public.devotionals(id) on delete cascade,
  created_at     timestamptz not null default now(),
  unique (user_id, devotional_id)
);

create index if not exists idx_devotional_bookmarks_user_created
  on public.devotional_bookmarks (user_id, created_at desc);

alter table public.devotional_bookmarks enable row level security;

create policy "devotional_bookmarks_own"
  on public.devotional_bookmarks for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (
    user_id = public.current_profile_id()
    and exists (
      select 1 from public.devotionals d
      where d.id = devotional_id
        and d.parish_id = public.current_parish_id()
        and d.status in ('published', 'scheduled')
        and d.publish_date <= current_date
    )
  );
