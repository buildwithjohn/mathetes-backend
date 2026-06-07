-- 0011_verse_images.sql
-- Verse image generator gallery. Images are rendered server-side (@vercel/og in
-- the admin app), cached in the public `verse-images` storage bucket, and a row
-- is recorded here per generation for the user's personal gallery.

create table if not exists public.verse_images (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.user_profiles(id) on delete cascade,
  verse_ref    text not null,
  verse_text   text not null,
  theme        text not null default 'minimal'
                 check (theme in ('minimal', 'organic', 'bold')),
  aspect_ratio text not null default 'square'
                 check (aspect_ratio in ('square', 'story')),
  watermark    boolean not null default true,
  url          text not null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_verse_images_user on public.verse_images (user_id, created_at desc);

alter table public.verse_images enable row level security;

-- A user's gallery is private to them.
create policy "verse_images_own" on public.verse_images for all
  to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());
