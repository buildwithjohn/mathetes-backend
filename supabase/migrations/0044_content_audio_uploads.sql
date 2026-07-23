-- 0044_content_audio_uploads.sql
-- Browser and recorder MIME labels for M4A/WebM vary by device. Accept the
-- common labels alongside the existing audio types so the Admin devotional
-- narration uploader works reliably on macOS, Android, and iOS.

update storage.buckets
set allowed_mime_types = (
  select array_agg(distinct mime order by mime)
  from unnest(
    coalesce(allowed_mime_types, array[]::text[])
    || array['audio/x-m4a', 'audio/webm']::text[]
  ) as mime
)
where id = 'content-media';
