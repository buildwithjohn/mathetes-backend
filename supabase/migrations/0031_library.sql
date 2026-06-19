-- 0031_library.sql
-- Parish Library / media hub: books, monthly devotional manuals, audio sermons,
-- and occasional community videos. The mobile app reads published items and
-- opens file_url / external_url directly (no deep-linking). Manuals
-- (kind='manual') are the monthly devotional booklets, distinct from the daily
-- devotionals table.
--
--   * RLS: members SELECT only published rows in their parish; pastor/admin have
--     full write within their parish (and see drafts). No member writes.
--   * Files live in the existing `content-media` bucket (this migration widens
--     it to allow PDFs + cover images and raises the size limit for books/video).

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------

create table if not exists public.library_items (
  id              uuid primary key default gen_random_uuid(),
  parish_id       uuid not null references public.parishes(id) on delete cascade,
  kind            text not null check (kind in ('book','manual','audio','video')),
  title           text not null,
  description     text,
  author          text,                       -- author / speaker name
  category        text,                        -- free tag: "September 2026", topic, ...
  cover_image_url text,
  file_url        text,                        -- the PDF/audio/video in content-media
  external_url    text,                        -- optional link (e.g. a YouTube URL)
  duration_seconds int,                        -- audio/video length
  published       boolean not null default false,
  published_at    timestamptz,
  author_id       uuid references public.user_profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists idx_library_items_parish_pub
  on public.library_items (parish_id, published, published_at desc);

-- updated_at maintenance (set_updated_at from 0002).
drop trigger if exists trg_library_items_updated_at on public.library_items;
create trigger trg_library_items_updated_at before update on public.library_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. RLS: members read published-in-parish; pastor/admin full write in-parish.
-- ---------------------------------------------------------------------------

alter table public.library_items enable row level security;

drop policy if exists "library_items_select_published" on public.library_items;
create policy "library_items_select_published" on public.library_items for select
  to authenticated
  using (published = true and parish_id = public.current_parish_id());

-- Pastor/admin: full read+write within their parish (this also exposes drafts to
-- admins). No member write path exists, so members can never insert/update/delete.
drop policy if exists "library_items_admin_all" on public.library_items;
create policy "library_items_admin_all" on public.library_items for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- ---------------------------------------------------------------------------
-- 3. Storage: reuse the `content-media` bucket. Widen the allowed MIME types
--    (PDFs for books/manuals, cover images) and raise the size limit so books
--    and video can be hosted. Read is public-by-URL (as set in 0019, matching
--    devotional media) so the app can open file_url/external_url in a browser;
--    only pastor/admin may write (the 0019 write policy still applies).
--    Idempotent: creates the bucket if missing, else updates limits/MIME types.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('content-media', 'content-media', true, 524288000, array[
  'application/pdf',
  'audio/mpeg','audio/mp4','audio/aac','audio/wav','audio/ogg',
  'video/mp4','video/webm','video/quicktime',
  'image/jpeg','image/png','image/webp'
])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
