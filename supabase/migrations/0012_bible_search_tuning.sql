-- 0012_bible_search_tuning.sql
-- Refine search_bible ranking. English full-text search drops common stop words
-- ('not', 'unto', ...) and stems aggressively, so a phrase like "lean not unto"
-- reduces to just 'lean' and ranks by term frequency (e.g. Isaiah 24:16's
-- repeated "leanness" outranks Proverbs 3:5). Add a literal phrase-substring
-- boost so verses that actually contain the typed phrase sort first, while
-- still returning the broader full-text matches below them.
--
-- The ILIKE is evaluated only over the GIN-filtered match set, so it stays cheap.

create or replace function public.search_bible(query text, version_code text default 'KJV', max_results int default 50)
returns table (
  verse_id  uuid,
  reference text,
  book_name text,
  chapter   int,
  verse     int,
  text      text,
  rank      real
)
language sql
stable
as $$
  select
    v.id,
    b.name || ' ' || c.number || ':' || v.number as reference,
    b.name,
    c.number,
    v.number,
    v.text,
    ts_rank(v.search_vector, websearch_to_tsquery('english', query)) as rank
  from public.bible_verses v
  join public.bible_chapters c on c.id = v.chapter_id
  join public.bible_books b on b.id = c.book_id
  join public.bible_versions ver on ver.id = b.version_id
  where ver.code = version_code
    and v.search_vector @@ websearch_to_tsquery('english', query)
  order by
    (v.text ilike '%' || query || '%') desc,   -- exact phrase first
    ts_rank(v.search_vector, websearch_to_tsquery('english', query)) desc,
    b.book_order, c.number, v.number
  limit greatest(max_results, 1);
$$;
