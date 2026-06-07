-- seed.sql
-- Development fixtures applied by `supabase db reset` (after migrations).
-- Real KJV scripture. author_id left null (no seeded auth users in local dev).

-- Today's Word of the Day for the pilot parish.
insert into public.word_of_day (parish_id, verse_ref, verse_text, reflection_md, prompt, publish_date, status)
values (
  '00000000-0000-0000-0000-000000000001',
  'Proverbs 3:5',
  'Trust in the LORD with all thine heart; and lean not unto thine own understanding.',
  'Trust is not the absence of thinking. It is the surrender of the throne. Your understanding is a gift, but it was never meant to be your god. Today, where are you leaning on yourself when He is asking you to lean on Him?',
  'What is one decision you are carrying alone that you can hand to God today?',
  current_date,
  'published'
)
on conflict (parish_id, publish_date) where publish_date is not null do nothing;

-- Tomorrow's Word of the Day (scheduled).
insert into public.word_of_day (parish_id, verse_ref, verse_text, reflection_md, publish_date, status)
values (
  '00000000-0000-0000-0000-000000000001',
  'Lamentations 3:23',
  'They are new every morning: great is thy faithfulness.',
  'Yesterday''s mercy has expired. Do not try to live today on it. He has already prepared a fresh portion for this morning. Receive it.',
  current_date + 1,
  'scheduled'
)
on conflict (parish_id, publish_date) where publish_date is not null do nothing;

-- A starter devotional series.
insert into public.devotional_series (id, parish_id, title, description, total_days)
values (
  '00000000-0000-0000-0000-000000000f01',
  '00000000-0000-0000-0000-000000000001',
  'Walking with the Master',
  'A seven-day walk through what it means to follow Jesus on campus.',
  7
)
on conflict (id) do nothing;

-- Today's devotional.
insert into public.devotionals
  (parish_id, series_id, day_in_series, title, body_md, scripture_refs, reading_time_minutes, publish_date, status)
values (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000f01',
  1,
  'The First Step Is Surrender',
  'Following Jesus does not begin with effort. It begins with surrender.' || E'\n\n' ||
  'When Peter left his nets, he was not promised a salary or a title. He was promised a Person. "Follow me," Jesus said, "and I will make you fishers of men." The making came after the following.' || E'\n\n' ||
  'On this campus, you will be tempted to follow many things: grades, status, relationships, applause. None of them can make you. Only One can. Today, lay down the net you have been clutching and take the first step.',
  array['Matthew 4:19', 'Luke 9:23'],
  3,
  current_date,
  'published'
)
on conflict (parish_id, publish_date) where publish_date is not null do nothing;

-- ---------------------------------------------------------------------------
-- Bible sample (real KJV). The full 66-book / 31,102-verse KJV import is a
-- large data file loaded separately (see README); this curated sample is
-- enough to exercise search_bible / parse_reference / get_chapter in dev.
-- ---------------------------------------------------------------------------

-- Chapters (verse_count is maintained by trigger as verses are inserted).
insert into public.bible_chapters (book_id, number)
select b.id, c.num
from (values ('Ps', 23), ('Prov', 3), ('John', 3)) as c(abbrev, num)
join public.bible_books b on b.abbrev = c.abbrev
join public.bible_versions v on v.id = b.version_id and v.code = 'KJV'
on conflict (book_id, number) do nothing;

-- Verses.
with ch as (
  select c.id, b.abbrev, c.number
  from public.bible_chapters c
  join public.bible_books b on b.id = c.book_id
  join public.bible_versions v on v.id = b.version_id and v.code = 'KJV'
)
insert into public.bible_verses (chapter_id, number, text)
select ch.id, d.num, d.text
from (values
  ('Ps', 23, 1, 'The LORD is my shepherd; I shall not want.'),
  ('Ps', 23, 2, 'He maketh me to lie down in green pastures: he leadeth me beside the still waters.'),
  ('Ps', 23, 3, 'He restoreth my soul: he leadeth me in the paths of righteousness for his name''s sake.'),
  ('Ps', 23, 4, 'Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me.'),
  ('Ps', 23, 5, 'Thou preparest a table before me in the presence of mine enemies: thou anointest my head with oil; my cup runneth over.'),
  ('Ps', 23, 6, 'Surely goodness and mercy shall follow me all the days of my life: and I will dwell in the house of the LORD for ever.'),
  ('Prov', 3, 5, 'Trust in the LORD with all thine heart; and lean not unto thine own understanding.'),
  ('Prov', 3, 6, 'In all thy ways acknowledge him, and he shall direct thy paths.'),
  ('John', 3, 16, 'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.')
) as d(abbrev, chap, num, text)
join ch on ch.abbrev = d.abbrev and ch.number = d.chap
on conflict (chapter_id, number) do nothing;
