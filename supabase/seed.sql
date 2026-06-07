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
