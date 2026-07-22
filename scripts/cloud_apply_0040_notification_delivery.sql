-- Paste this entire file into the Supabase SQL Editor for project
-- jowokfnlfqqjzwhvnmxj only if `supabase db push` cannot run because the
-- migration history predates this repository checkout. It is idempotent.

alter table public.notifications
  drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type in ('message', 'announcement', 'devotional', 'ask_answered', 'mention', 'daily_prompt', 'streak', 'prayer', 'system'));

create or replace function public.notify_on_devotional()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published' and (new.publish_date is null or new.publish_date <= current_date)
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'devotional', coalesce(nullif(new.title, ''), 'Today''s devotional'),
           left(new.body_md, 140), new.id, 'mathetes://devotional/' || new.id
    from public.user_profiles p
    where p.parish_id = new.parish_id and p.status = 'active' and p.id is distinct from new.author_id
      and not exists (select 1 from public.notifications n where n.type = 'devotional' and n.target_id = new.id and n.user_id = p.id)
      and not exists (select 1 from public.notification_preferences np where np.user_id = p.id and np.type = 'devotional' and np.channel = 'in_app' and np.enabled = false);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_on_devotional on public.devotionals;
create trigger trg_notify_on_devotional after insert or update of status on public.devotionals
  for each row execute function public.notify_on_devotional();

create or replace function public.notify_on_word_of_day()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published' and (new.publish_date is null or new.publish_date <= current_date)
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'system', 'Today''s Word', new.verse_ref, new.id,
           'mathetes://word/' || coalesce(new.publish_date::text, current_date::text)
    from public.user_profiles p
    where p.parish_id = new.parish_id and p.status = 'active' and p.id is distinct from new.author_id
      and not exists (select 1 from public.notifications n where n.type = 'system' and n.target_id = new.id and n.user_id = p.id)
      and not exists (select 1 from public.notification_preferences np where np.user_id = p.id and np.type = 'system' and np.channel = 'in_app' and np.enabled = false);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_on_word_of_day on public.word_of_day;
create trigger trg_notify_on_word_of_day after insert or update of status on public.word_of_day
  for each row execute function public.notify_on_word_of_day();
