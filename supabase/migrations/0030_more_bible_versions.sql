-- 0030_more_bible_versions.sql
-- Add three public-domain Bible translations alongside KJV. The reader's
-- translation switcher is driven by bible_versions, so each version needs its
-- own version row + 66 books; the full verse text is bulk-loaded from
-- supabase/seed/{web,bsb,asv}.sql (same mechanism as KJV — not run by this
-- migration; load via scripts/load-bible.sh or the SQL editor).
--
--   WEB  World English Bible        Public Domain (modern, readable)
--   BSB  Berean Standard Bible      Public Domain (attribution appreciated)
--   ASV  American Standard Version  Public Domain (1901)
--
-- COPYRIGHTED translations (NKJV - Thomas Nelson/HarperCollins; NLT - Tyndale)
-- are intentionally NOT added: importing their text without a written licence /
-- API agreement is infringement. Add them only after licensing directly or via
-- a licensed Bible API (e.g. API.Bible) under its terms.
--
-- Idempotent: re-running inserts nothing new.

-- ---------------------------------------------------------------------------
-- 1. Version rows (fixed UUIDs so the seed files + types stay deterministic).
-- ---------------------------------------------------------------------------

insert into public.bible_versions (id, code, name, language, license, version)
values
  ('00000000-0000-0000-0000-0000000b1b02', 'WEB', 'World English Bible',       'en', 'Public Domain',                          '2010'),
  ('00000000-0000-0000-0000-0000000b1b03', 'BSB', 'Berean Standard Bible',     'en', 'Public Domain (attribution appreciated)', '2023'),
  ('00000000-0000-0000-0000-0000000b1b04', 'ASV', 'American Standard Version', 'en', 'Public Domain',                          '1901')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The 66 books for each new version (same canonical order/abbrev/testament
--    as KJV). Cross-join the book list with the three new versions so the list
--    is declared once.
-- ---------------------------------------------------------------------------

insert into public.bible_books (version_id, name, abbrev, testament, book_order)
select ver.id, d.name, d.abbrev, d.testament, d.ord
from public.bible_versions ver
cross join (values
  ('Genesis','Gen','OT',1),('Exodus','Exod','OT',2),('Leviticus','Lev','OT',3),
  ('Numbers','Num','OT',4),('Deuteronomy','Deut','OT',5),('Joshua','Josh','OT',6),
  ('Judges','Judg','OT',7),('Ruth','Ruth','OT',8),('1 Samuel','1Sam','OT',9),
  ('2 Samuel','2Sam','OT',10),('1 Kings','1Kgs','OT',11),('2 Kings','2Kgs','OT',12),
  ('1 Chronicles','1Chr','OT',13),('2 Chronicles','2Chr','OT',14),('Ezra','Ezra','OT',15),
  ('Nehemiah','Neh','OT',16),('Esther','Esth','OT',17),('Job','Job','OT',18),
  ('Psalms','Ps','OT',19),('Proverbs','Prov','OT',20),('Ecclesiastes','Eccl','OT',21),
  ('Song of Solomon','Song','OT',22),('Isaiah','Isa','OT',23),('Jeremiah','Jer','OT',24),
  ('Lamentations','Lam','OT',25),('Ezekiel','Ezek','OT',26),('Daniel','Dan','OT',27),
  ('Hosea','Hos','OT',28),('Joel','Joel','OT',29),('Amos','Amos','OT',30),
  ('Obadiah','Obad','OT',31),('Jonah','Jonah','OT',32),('Micah','Mic','OT',33),
  ('Nahum','Nah','OT',34),('Habakkuk','Hab','OT',35),('Zephaniah','Zeph','OT',36),
  ('Haggai','Hag','OT',37),('Zechariah','Zech','OT',38),('Malachi','Mal','OT',39),
  ('Matthew','Matt','NT',40),('Mark','Mark','NT',41),('Luke','Luke','NT',42),
  ('John','John','NT',43),('Acts','Acts','NT',44),('Romans','Rom','NT',45),
  ('1 Corinthians','1Cor','NT',46),('2 Corinthians','2Cor','NT',47),('Galatians','Gal','NT',48),
  ('Ephesians','Eph','NT',49),('Philippians','Phil','NT',50),('Colossians','Col','NT',51),
  ('1 Thessalonians','1Thess','NT',52),('2 Thessalonians','2Thess','NT',53),('1 Timothy','1Tim','NT',54),
  ('2 Timothy','2Tim','NT',55),('Titus','Titus','NT',56),('Philemon','Phlm','NT',57),
  ('Hebrews','Heb','NT',58),('James','Jas','NT',59),('1 Peter','1Pet','NT',60),
  ('2 Peter','2Pet','NT',61),('1 John','1John','NT',62),('2 John','2John','NT',63),
  ('3 John','3John','NT',64),('Jude','Jude','NT',65),('Revelation','Rev','NT',66)
) as d(name, abbrev, testament, ord)
where ver.code in ('WEB','BSB','ASV')
on conflict (version_id, book_order) do nothing;
