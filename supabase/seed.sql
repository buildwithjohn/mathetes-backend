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


-- ---------------------------------------------------------------------------
-- V2.0 reading plan sample (dev only). "First 30 Days of Following Jesus".
-- author_id left null (no seeded auth user in local dev; the pastor account
-- exists only in cloud). Published for dev convenience; the pastor republishes
-- with final content. Every day's reflection_body is clearly marked PLACEHOLDER.
-- ---------------------------------------------------------------------------

insert into public.reading_plans
  (id, parish_id, slug, title, description, length_days, difficulty, sequence_locked, published, published_at)
values (
  '00000000-0000-0000-0000-00000000d001',
  '00000000-0000-0000-0000-000000000001',
  'first-30-days',
  'First 30 Days of Following Jesus',
  'A starter journey through the Gospels for new disciples: one passage and one short reflection a day for thirty days.',
  30, 'starter', true, true, now()
)
on conflict (parish_id, slug) do nothing;

insert into public.reading_plan_days
  (plan_id, day_number, title, scripture_reference, reflection_body, reflection_prompt)
select
  '00000000-0000-0000-0000-00000000d001',
  d,
  'Day ' || d || ': ' || (array[
    'The Word Became Flesh','The Kingdom Comes Near','Called to Follow','Born Again',
    'The Heart of the Sermon','How to Pray','The Father Who Runs','Living Water',
    'The Sower','Come Unto Me','The Bread of Life','Love Your Neighbour',
    'Take Courage','Grace and Truth','Who Do You Say I Am','Two Men Prayed',
    'The Good Shepherd','Forgiven to Forgive','Sought and Saved','I Am the Resurrection',
    'One Thing You Lack','The Greatest Commandment','He Washed Their Feet','Do Not Be Troubled',
    'The True Vine','Not My Will','The Cross','It Is Finished',
    'He Is Risen','Do You Love Me'])[d],
  (array[
    'John 1:1-18','Mark 1:1-20','Luke 5:1-11','John 3:1-21','Matthew 5:1-16','Matthew 6:5-15',
    'Luke 15:11-32','John 4:1-26','Mark 4:1-20','Matthew 11:25-30','John 6:25-40','Luke 10:25-37',
    'Matthew 14:22-33','John 1:14-18','Mark 8:27-38','Luke 18:9-14','John 10:1-18','Matthew 18:21-35',
    'Luke 19:1-10','John 11:17-44','Mark 10:17-31','Matthew 22:34-40','John 13:1-17','John 14:1-14',
    'John 15:1-17','Luke 22:39-46','Mark 15:21-39','John 19:28-42','Luke 24:1-12','John 21:15-25'])[d],
  'PLACEHOLDER - pastor authors final. A short reflection on today''s passage and what it means to follow Jesus on campus.',
  'PLACEHOLDER - reflection prompt for day ' || d || ': what is one thing this passage asks of you today?'
from generate_series(1, 30) as d
on conflict (plan_id, day_number) do nothing;
