-- 0015_chat_media.sql
-- Storage for chat message media (images and voice notes), plus a fix that
-- makes the avatars bucket public.
--
-- Why avatars becomes public: the Mathetes apps reference profile photos and
-- chat media by their public object URL (storage getPublicUrl). A private
-- bucket only serves bytes through authenticated/signed requests, so the stored
-- public URLs 404. Profile photos are opt-in and chat media filenames are
-- unguessable (uploaded under the author's auth-UID folder), so public buckets
-- with random paths are an acceptable pilot tradeoff. Tighten to signed URLs
-- later if stricter privacy is required.

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------

update storage.buckets set public = true where id = 'avatars';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('chat-media', 'chat-media', true, 26214400,
   array['image/png','image/jpeg','image/webp',
         'audio/m4a','audio/mp4','audio/mpeg','audio/aac','audio/x-m4a'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- chat-media: public read (served by URL); authenticated users write only into
-- their own auth-UID folder, mirroring the avatars / verse-images convention.
-- Who may see a given message is governed by the messages RLS (can_read_chat);
-- this bucket just stores the bytes.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_chat_media_read"       on storage.objects;
drop policy if exists "mathetes_chat_media_insert_own" on storage.objects;
drop policy if exists "mathetes_chat_media_update_own" on storage.objects;
drop policy if exists "mathetes_chat_media_delete_own" on storage.objects;

create policy "mathetes_chat_media_read" on storage.objects for select
  using (bucket_id = 'chat-media');

create policy "mathetes_chat_media_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_chat_media_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_chat_media_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);
