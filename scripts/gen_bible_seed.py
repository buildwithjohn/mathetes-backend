#!/usr/bin/env python3
"""Generate a per-version Bible seed SQL file (same format as supabase/seed/kjv.sql).

Public-domain sources (no licence/agreement required):
  WEB  World English Bible          gratis-bible (OSIS XML)
  BSB  Berean Standard Bible        scrollmapper/bible_databases (JSON)
  ASV  American Standard Version    scrollmapper/bible_databases (JSON)

Each translation is keyed to its own bible_versions row + 66 books (seeded by
migration 0030). This script downloads the source, normalises it to
(book_order, chapter, verse, text) over the canonical 66-book Protestant canon,
and writes supabase/seed/<code-lower>.sql with a COPY block + chapter/verse
inserts that join on book_order and the version code.

Usage:
  python3 scripts/gen_bible_seed.py web   > supabase/seed/web.sql
  python3 scripts/gen_bible_seed.py bsb   > supabase/seed/bsb.sql
  python3 scripts/gen_bible_seed.py asv   > supabase/seed/asv.sql

Re-running is deterministic. The emitted SQL is idempotent (on conflict do nothing).
"""
import csv
import io
import json
import re
import sys
import urllib.request

# Canonical 66 books in order 1..66 (matches 0003_bible.sql). The OSIS book code
# used by the WEB source equals the schema `abbrev`, so this one table serves
# both the index-based (JSON) and code-based (OSIS) mappings.
BOOKS = [
    ("Genesis", "Gen"), ("Exodus", "Exod"), ("Leviticus", "Lev"), ("Numbers", "Num"),
    ("Deuteronomy", "Deut"), ("Joshua", "Josh"), ("Judges", "Judg"), ("Ruth", "Ruth"),
    ("1 Samuel", "1Sam"), ("2 Samuel", "2Sam"), ("1 Kings", "1Kgs"), ("2 Kings", "2Kgs"),
    ("1 Chronicles", "1Chr"), ("2 Chronicles", "2Chr"), ("Ezra", "Ezra"), ("Nehemiah", "Neh"),
    ("Esther", "Esth"), ("Job", "Job"), ("Psalms", "Ps"), ("Proverbs", "Prov"),
    ("Ecclesiastes", "Eccl"), ("Song of Solomon", "Song"), ("Isaiah", "Isa"), ("Jeremiah", "Jer"),
    ("Lamentations", "Lam"), ("Ezekiel", "Ezek"), ("Daniel", "Dan"), ("Hosea", "Hos"),
    ("Joel", "Joel"), ("Amos", "Amos"), ("Obadiah", "Obad"), ("Jonah", "Jonah"),
    ("Micah", "Mic"), ("Nahum", "Nah"), ("Habakkuk", "Hab"), ("Zephaniah", "Zeph"),
    ("Haggai", "Hag"), ("Zechariah", "Zech"), ("Malachi", "Mal"), ("Matthew", "Matt"),
    ("Mark", "Mark"), ("Luke", "Luke"), ("John", "John"), ("Acts", "Acts"),
    ("Romans", "Rom"), ("1 Corinthians", "1Cor"), ("2 Corinthians", "2Cor"), ("Galatians", "Gal"),
    ("Ephesians", "Eph"), ("Philippians", "Phil"), ("Colossians", "Col"), ("1 Thessalonians", "1Thess"),
    ("2 Thessalonians", "2Thess"), ("1 Timothy", "1Tim"), ("2 Timothy", "2Tim"), ("Titus", "Titus"),
    ("Philemon", "Phlm"), ("Hebrews", "Heb"), ("James", "Jas"), ("1 Peter", "1Pet"),
    ("2 Peter", "2Pet"), ("1 John", "1John"), ("2 John", "2John"), ("3 John", "3John"),
    ("Jude", "Jude"), ("Revelation", "Rev"),
]
ABBREV_TO_ORDER = {abbrev: i + 1 for i, (_, abbrev) in enumerate(BOOKS)}

SOURCES = {
    "web": {
        "code": "WEB",
        "url": "https://raw.githubusercontent.com/gratis-bible/bible/master/en/web.xml",
        "fmt": "osis",
    },
    "bsb": {
        "code": "BSB",
        "url": "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/BSB.json",
        "fmt": "scrollmapper",
    },
    "asv": {
        "code": "ASV",
        "url": "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/ASV.json",
        "fmt": "scrollmapper",
    },
}


def clean(text: str) -> str:
    # Normalise the WEB source's backtick-as-apostrophe and collapse whitespace.
    text = text.replace("`", "'")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "mathetes-bible-seed/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def rows_scrollmapper(raw: bytes):
    """scrollmapper JSON: books[] in canonical order (index -> book_order)."""
    data = json.loads(raw)
    books = data["books"]
    if len(books) != 66:
        raise SystemExit(f"expected 66 books, got {len(books)}")
    for idx, book in enumerate(books):
        order = idx + 1
        for ch in book["chapters"]:
            cnum = int(ch["chapter"])
            for v in ch["verses"]:
                txt = clean(v["text"])
                if txt:
                    yield (order, cnum, int(v["verse"]), txt)


def rows_osis(raw: bytes):
    """OSIS container-style: <verse osisID='Book.C.V'>text</verse>, Book == abbrev."""
    xml = raw.decode("utf-8")
    pat = re.compile(r"<verse osisID='([^']+)'>(.*?)</verse>", re.DOTALL)
    unescape = lambda s: (s.replace("&apos;", "'").replace("&quot;", '"')
                            .replace("&lt;", "<").replace("&gt;", ">")
                            .replace("&amp;", "&"))
    for osis_id, body in pat.findall(xml):
        parts = osis_id.split(".")
        if len(parts) != 3:
            continue
        book_code, ch, vs = parts
        order = ABBREV_TO_ORDER.get(book_code)
        if order is None:          # skip anything outside the 66-book canon
            continue
        txt = clean(unescape(body))
        if txt:
            yield (order, int(ch), int(vs), txt)


HEADER = """-- seed/{lower}.sql
-- {name} ({code}) - {license}. {nbooks} books, {nchap} chapters, {nverse} verses.
-- Source: {url}
-- Generated by scripts/gen_bible_seed.py. Idempotent: safe to re-run. Loads
-- against the {code} version + 66 books seeded by migration 0030, joining on
-- canonical book_order.
--
-- Not auto-run by `supabase db reset`. Load explicitly:
--     ./scripts/load-bible.sh {lower}   # or: psql ... -f supabase/seed/{lower}.sql

begin;

-- Skip the per-row verse_count recompute during bulk load; fix up in one pass.
-- (search_vector is still maintained by its BEFORE trigger.)
alter table public.bible_verses disable trigger trg_bible_verse_count;

create temp table _bible_stage (book_order int, chapter int, verse int, text text) on commit drop;

copy _bible_stage (book_order, chapter, verse, text) from stdin with (format csv);
"""

FOOTER = """\\.

insert into public.bible_chapters (book_id, number)
select b.id, s.chapter
from (select distinct book_order, chapter from _bible_stage) s
join public.bible_books b on b.book_order = s.book_order
join public.bible_versions ver on ver.id = b.version_id and ver.code = '{code}'
on conflict (book_id, number) do nothing;

insert into public.bible_verses (chapter_id, number, text)
select c.id, s.verse, s.text
from _bible_stage s
join public.bible_books b on b.book_order = s.book_order
join public.bible_versions ver on ver.id = b.version_id and ver.code = '{code}'
join public.bible_chapters c on c.book_id = b.id and c.number = s.chapter
on conflict (chapter_id, number) do nothing;

alter table public.bible_verses enable trigger trg_bible_verse_count;

update public.bible_chapters c
  set verse_count = sub.n
from (select chapter_id, count(*) n from public.bible_verses group by chapter_id) sub
where sub.chapter_id = c.id and c.verse_count <> sub.n;

commit;
"""

LICENSE = {
    "WEB": "Public Domain",
    "BSB": "Public Domain (attribution appreciated)",
    "ASV": "Public Domain",
}
NAME = {
    "WEB": "World English Bible",
    "BSB": "Berean Standard Bible",
    "ASV": "American Standard Version",
}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in SOURCES:
        raise SystemExit("usage: gen_bible_seed.py {web|bsb|asv}")
    key = sys.argv[1]
    src = SOURCES[key]
    code = src["code"]
    raw = fetch(src["url"])
    gen = rows_scrollmapper if src["fmt"] == "scrollmapper" else rows_osis
    rows = sorted(gen(raw))

    nverse = len(rows)
    nchap = len({(o, c) for (o, c, _, _) in rows})
    nbooks = len({o for (o, _, _, _) in rows})
    if nbooks != 66:
        raise SystemExit(f"{code}: expected 66 books, got {nbooks}")

    out = sys.stdout
    out.write(HEADER.format(lower=key, name=NAME[code], code=code, license=LICENSE[code],
                            nbooks=nbooks, nchap=nchap, nverse=nverse, url=src["url"]))
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    for r in rows:
        w.writerow(r)
    out.write(buf.getvalue())
    out.write(FOOTER.format(code=code))


if __name__ == "__main__":
    main()
