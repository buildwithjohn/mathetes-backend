-- Editorial cover artwork authored by pastors for daily content.
alter table public.devotionals
  add column if not exists cover_image_url text;

alter table public.word_of_day
  add column if not exists cover_image_url text;
