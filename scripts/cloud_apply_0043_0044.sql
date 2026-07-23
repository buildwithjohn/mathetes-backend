-- Apply migrations 0043 and 0044 from the Supabase SQL editor if CLI push is
-- unavailable. Safe to run more than once.

-- 0043_message_notification_sender.sql
create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_kind        text;
  v_parish      uuid;
  v_house       uuid;
  v_title       text;
  v_type        text;
  v_preview     text;
  v_sender_name text;
begin
  if new.deleted_at is not null or new.kind = 'system' then
    return new;
  end if;

  select kind, parish_id, house_id into v_kind, v_parish, v_house
    from public.chats where id = new.chat_id;

  select coalesce(nullif(btrim(name), ''), 'Someone') into v_sender_name
    from public.user_profiles
    where id = new.author_id;
  v_sender_name := coalesce(v_sender_name, 'Someone');

  v_preview := left(coalesce(new.body, case new.kind when 'voice' then 'Voice note'
                                                     when 'image' then 'Photo' else '' end), 140);

  if v_kind = 'announcements' then
    v_type := 'announcement';
    v_title := 'Announcement · ' || v_sender_name;
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
    v_title := case when new.kind = 'daily_prompt' then 'Today''s prompt' else v_sender_name end;
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

-- 0044_content_audio_uploads.sql
update storage.buckets
set allowed_mime_types = (
  select array_agg(distinct mime order by mime)
  from unnest(
    coalesce(allowed_mime_types, array[]::text[])
    || array['audio/x-m4a', 'audio/webm']::text[]
  ) as mime
)
where id = 'content-media';
