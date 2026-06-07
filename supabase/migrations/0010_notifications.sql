-- 0010_notifications.sql
-- Notifications: Expo push tokens, the in-app notification feed, and per-type
-- delivery preferences. In-app notification rows are created by triggers (and
-- the daily-content-publish job); the send-push edge function fans them out to
-- Expo, consulting notification_preferences before pushing.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.push_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  expo_token text unique not null,
  platform   text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.user_profiles(id) on delete cascade,
  type       text not null
               check (type in ('message', 'announcement', 'ask_answered',
                               'mention', 'daily_prompt', 'streak', 'prayer', 'system')),
  title      text not null,
  preview    text,
  target_id  uuid,        -- chat_id / question_id / prayer_id, etc.
  target_url text,        -- optional deep link (e.g. 'mathetes://chat/<id>')
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create table if not exists public.notification_preferences (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  type    text not null,
  channel text not null check (channel in ('push', 'in_app')),
  enabled boolean not null default true,
  primary key (user_id, type, channel)
);

create index if not exists idx_push_tokens_user on public.push_tokens (user_id);
create index if not exists idx_notifications_user_unread
  on public.notifications (user_id, created_at desc) where read_at is null;
create index if not exists idx_notifications_user on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Notification creation helpers (SECURITY DEFINER: triggers create rows for
-- OTHER users, which RLS would otherwise forbid).
-- ---------------------------------------------------------------------------

create or replace function public.create_notification(
  p_user uuid, p_type text, p_title text,
  p_preview text default null, p_target_id uuid default null, p_target_url text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- Honour an explicit in-app opt-out for this type.
  if exists (
    select 1 from public.notification_preferences
    where user_id = p_user and type = p_type and channel = 'in_app' and enabled = false
  ) then
    return;
  end if;

  insert into public.notifications (user_id, type, title, preview, target_id, target_url)
  values (p_user, p_type, p_title, p_preview, p_target_id, p_target_url);
end;
$$;

-- New message -> notify the other participants (or, for announcements, the
-- whole parish), skipping the author and anyone who muted the chat.
create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_kind   text;
  v_parish uuid;
  v_house  uuid;
  v_title  text;
  v_type   text;
  v_preview text;
begin
  if new.deleted_at is not null or new.kind = 'system' then
    return new;
  end if;

  select kind, parish_id, house_id into v_kind, v_parish, v_house
    from public.chats where id = new.chat_id;

  v_preview := left(coalesce(new.body, case new.kind when 'voice' then 'Voice note'
                                                     when 'image' then 'Photo' else '' end), 140);

  if v_kind = 'announcements' then
    v_type := 'announcement';
    v_title := 'Parish announcement';
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select p.id, v_type, v_title, v_preview, new.chat_id, 'mathetes://chat/' || new.chat_id
    from public.user_profiles p
    where p.parish_id = v_parish
      and p.id <> coalesce(new.author_id, '00000000-0000-0000-0000-000000000000')
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = p.id and np.type = v_type and np.channel = 'in_app' and np.enabled = false
      );
  else
    v_type := case when new.kind = 'daily_prompt' then 'daily_prompt' else 'message' end;
    v_title := case when new.kind = 'daily_prompt' then 'Today''s prompt' else 'New message' end;
    insert into public.notifications (user_id, type, title, preview, target_id, target_url)
    select m.user_id, v_type, v_title, v_preview, new.chat_id, 'mathetes://chat/' || new.chat_id
    from public.chat_members m
    where m.chat_id = new.chat_id
      and m.muted = false
      and m.user_id <> coalesce(new.author_id, '00000000-0000-0000-0000-000000000000')
      and not exists (
        select 1 from public.notification_preferences np
        where np.user_id = m.user_id and np.type = v_type and np.channel = 'in_app' and np.enabled = false
      );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_message on public.messages;
create trigger trg_notify_on_message
  after insert on public.messages
  for each row execute function public.notify_on_message();

-- Ask-pastor answered -> notify the asker.
create or replace function public.notify_on_answer()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'answered' and (old.status is distinct from 'answered') then
    perform public.create_notification(
      new.asker_id, 'ask_answered', 'Pastor answered your question',
      left(coalesce(new.response_body, ''), 140), new.id, 'mathetes://ask-pastor/' || new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_answer on public.ask_questions;
create trigger trg_notify_on_answer
  after update of status on public.ask_questions
  for each row execute function public.notify_on_answer();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.push_tokens              enable row level security;
alter table public.notifications            enable row level security;
alter table public.notification_preferences enable row level security;

-- Push tokens: register / read / remove your own device tokens.
create policy "push_tokens_own" on public.push_tokens for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- Notifications: read your own; mark them read (UPDATE). Rows are created by
-- SECURITY DEFINER triggers / the service role, never directly by a member.
create policy "notifications_select_own" on public.notifications for select
  to authenticated
  using (user_id = public.current_profile_id());

create policy "notifications_update_own" on public.notifications for update
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

create policy "notifications_delete_own" on public.notifications for delete
  to authenticated
  using (user_id = public.current_profile_id());

-- Preferences: manage your own.
create policy "notification_preferences_own" on public.notification_preferences for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

-- ---------------------------------------------------------------------------
-- Realtime: clients live-update the notification bell.
-- ---------------------------------------------------------------------------

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      create publication supabase_realtime;
    exception when others then raise notice 'realtime: could not create publication: %', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
    begin
      alter publication supabase_realtime add table public.notifications;
    exception when others then raise notice 'realtime: could not add notifications: %', sqlerrm;
    end;
  end if;
end $$;
