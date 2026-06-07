-- 0013_storage.sql
-- Storage buckets + RLS for profile photos, devotional images, and verse
-- images. The cloud project was provisioned via psql (not the Supabase CLI), so
-- config.toml's bucket definitions were never created there; this migration
-- makes the buckets and their access rules reproducible in SQL.
--
-- Convention: a user's files live under a folder named for their auth UID, e.g.
-- 'avatars/<auth_uid>/photo.jpg'. Policies enforce that you may only write into
-- your own folder. Idempotent (drop-if-exists before create) so it is safe to
-- re-run against an existing project.

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',           'avatars',           false,  5242880, array['image/png','image/jpeg','image/webp']),
  ('devotional-images', 'devotional-images', true,  10485760, array['image/png','image/jpeg','image/webp']),
  ('verse-images',      'verse-images',      true,  10485760, array['image/png','image/jpeg'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- avatars: any authenticated user may read; you write only your own folder.
-- (Default photo is initials; uploads are opt-in — see the pastoral guardrails.)
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_avatars_read"        on storage.objects;
drop policy if exists "mathetes_avatars_insert_own"  on storage.objects;
drop policy if exists "mathetes_avatars_update_own"  on storage.objects;
drop policy if exists "mathetes_avatars_delete_own"  on storage.objects;

create policy "mathetes_avatars_read" on storage.objects for select
  to authenticated
  using (bucket_id = 'avatars');

create policy "mathetes_avatars_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_avatars_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_avatars_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- verse-images: public bucket (served by public URL); authenticated users write
-- only their own folder, mirroring the verse_images gallery rows.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_verse_images_read"       on storage.objects;
drop policy if exists "mathetes_verse_images_insert_own" on storage.objects;
drop policy if exists "mathetes_verse_images_update_own" on storage.objects;
drop policy if exists "mathetes_verse_images_delete_own" on storage.objects;

create policy "mathetes_verse_images_read" on storage.objects for select
  using (bucket_id = 'verse-images');

create policy "mathetes_verse_images_insert_own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_verse_images_update_own" on storage.objects for update
  to authenticated
  using (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "mathetes_verse_images_delete_own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'verse-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- devotional-images: public read; only pastor/admin may write parish content.
-- ---------------------------------------------------------------------------

drop policy if exists "mathetes_devo_images_read"  on storage.objects;
drop policy if exists "mathetes_devo_images_write" on storage.objects;

create policy "mathetes_devo_images_read" on storage.objects for select
  using (bucket_id = 'devotional-images');

create policy "mathetes_devo_images_write" on storage.objects for all
  to authenticated
  using (bucket_id = 'devotional-images' and public.is_parish_admin())
  with check (bucket_id = 'devotional-images' and public.is_parish_admin());
