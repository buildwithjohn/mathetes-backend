-- 0019_content_media.sql
-- Audio/video narration for devotionals. `audio_url` already exists (0002);
-- this adds `video_url` and a `content-media` storage bucket so the admin can
-- host audio/video alongside external links. Public read (served by URL); only
-- pastor/admin may write, mirroring devotional-images in 0013_storage.
-- Idempotent and safe to re-run.

alter table public.devotionals
  add column if not exists video_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('content-media', 'content-media', true, 104857600,
   array['audio/mpeg','audio/mp4','audio/aac','audio/wav','video/mp4','video/webm'])
on conflict (id) do nothing;

drop policy if exists "mathetes_content_media_read"  on storage.objects;
drop policy if exists "mathetes_content_media_write" on storage.objects;

create policy "mathetes_content_media_read" on storage.objects for select
  using (bucket_id = 'content-media');

create policy "mathetes_content_media_write" on storage.objects for all
  to authenticated
  using (bucket_id = 'content-media' and public.is_parish_admin())
  with check (bucket_id = 'content-media' and public.is_parish_admin());
