-- 0032_wotd_prayer.sql
-- Optional prayer guide for the Word of the Day: markdown the pastor writes to
-- accompany the verse, rendered by the app as a "Pray" section. Nullable; no RLS
-- change (same row, same access as the rest of word_of_day).

alter table public.word_of_day
  add column if not exists prayer_md text;

-- todays_word_of_day is `select *`, which snapshots the column list at creation
-- time; recreate it so the new column flows through to the app's "today" query.
create or replace view public.todays_word_of_day
with (security_invoker = true) as
  select *
  from public.word_of_day
  where status = 'published'
    and publish_date = current_date;
