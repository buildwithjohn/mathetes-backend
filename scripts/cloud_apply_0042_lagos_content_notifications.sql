-- Safe to paste into the Supabase SQL editor if CLI migration deployment is
-- unavailable. Kept aligned with migration 0042.

create or replace function public.notify_on_devotional()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Africa/Lagos')::date;
begin
  if new.status = 'published'
     and (new.publish_date is null or new.publish_date <= v_today)
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'devotional', coalesce(nullif(new.title, ''), 'Today''s devotional'),
           left(new.body_md, 140), new.id, 'mathetes://devotional/' || new.id
    from public.user_profiles p
    where p.parish_id = new.parish_id
      and p.status = 'active'
      and p.id is distinct from new.author_id
      and not exists (
        select 1 from public.notifications n
        where n.type = 'devotional' and n.target_id = new.id and n.user_id = p.id
      )
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = 'devotional'
          and np.channel = 'in_app' and np.enabled = false
      );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_devotional on public.devotionals;
create trigger trg_notify_on_devotional
  after insert or update of status, publish_date on public.devotionals
  for each row execute function public.notify_on_devotional();

create or replace function public.notify_on_word_of_day()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Africa/Lagos')::date;
begin
  if new.status = 'published'
     and (new.publish_date is null or new.publish_date <= v_today)
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, 'system', 'Today''s Word', new.verse_ref, new.id,
           'mathetes://word/' || coalesce(new.publish_date::text, v_today::text)
    from public.user_profiles p
    where p.parish_id = new.parish_id
      and p.status = 'active'
      and p.id is distinct from new.author_id
      and not exists (
        select 1 from public.notifications n
        where n.type = 'system' and n.target_id = new.id and n.user_id = p.id
      )
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = 'system'
          and np.channel = 'in_app' and np.enabled = false
      );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_word_of_day on public.word_of_day;
create trigger trg_notify_on_word_of_day
  after insert or update of status, publish_date on public.word_of_day
  for each row execute function public.notify_on_word_of_day();

do $$
declare
  v_today date := (now() at time zone 'Africa/Lagos')::date;
begin
  insert into public.notifications (user_id, type, title, preview, target_id, target_url)
  select p.id, 'devotional', coalesce(nullif(d.title, ''), 'Today''s devotional'),
         left(d.body_md, 140), d.id, 'mathetes://devotional/' || d.id
  from public.devotionals d
  join public.user_profiles p
    on p.parish_id = d.parish_id
   and p.status = 'active'
   and p.id is distinct from d.author_id
  where d.status = 'published'
    and d.publish_date = v_today
    and not exists (
      select 1 from public.notifications n
      where n.type = 'devotional' and n.target_id = d.id and n.user_id = p.id
    )
    and not exists (
      select 1 from public.notification_preferences np
      where np.user_id = p.id and np.type = 'devotional'
        and np.channel = 'in_app' and np.enabled = false
    );
end;
$$;
