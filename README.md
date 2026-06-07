# Mathetes Backend

Supabase project for Mathetes: Postgres schema, migrations, RLS policies, edge
functions, and seed data. Serves the CCCFSP FUOYE pilot parish (7 houses).

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) (`npm i -g supabase` or `brew install supabase/tap/supabase`)
- Docker (the local stack runs in containers)

## Getting started

```bash
# Start the local stack (Postgres, Auth, Storage, Studio, etc.)
supabase start

# Apply all migrations + seed from scratch
./scripts/reset-db.sh        # wraps `supabase db reset`

# Regenerate TypeScript types after a schema change
./scripts/generate-types.sh  # writes types.ts, copies to mobile + admin if present
```

`supabase start` prints your local `API URL`, `anon key`, and `service_role key`.
Copy them into the mobile and admin `.env` files.

## Migrations

| File | Adds |
|------|------|
| `0001_init_identity.sql` | parishes, houses, user_profiles, user_privacy; `handle_new_user` trigger; SECURITY DEFINER helpers (`current_parish_id`, `is_parish_admin`, etc.); RLS; CCCFSP FUOYE seed with 7 houses |
| `0002_content.sql` | devotional_series, devotionals, word_of_day, content_assets; one-per-parish-per-day unique indexes; RLS (members read published, admins write); `todays_word_of_day` / `todays_devotional` views |
| `0003_bible.sql` | bible_versions/books/chapters/verses; `tsvector` full-text search (GIN); `search_bible` / `get_chapter` / `parse_reference`; read-for-all RLS; KJV version + 66-book reference data |
| `0004_personal_library.sql` | notes, bookmarks, highlights, reading_position; owner-only RLS |
| `0005_engagement.sql` | streaks (monthly grace-day logic via `record_check_in`), engagement_events; owner RLS + parish-admin analytics read |
| `0006_chat.sql` | chats, chat_members, messages, message_reactions, pinned_messages; pastoral-oversight RLS; house-chat / discipler-chat automation; `create_dm` RPC; realtime publication; seeded announcements + 7 house chats |
| `0007_prayer_wall.sql` | prayer_requests, prayer_pray, prayer_reactions; house/parish-scoped RLS with house-leader visibility |
| `0008_ask_pastor.sql` | ask_questions queue; `answer_question` RPC; anonymized `public_qa` view (security-definer) |
| `0009_safety.sql` | blocks, reports, moderation_log; restrictive policy so a block hides the blocked user's messages |
| `0010_notifications.sql` | push_tokens, notifications, notification_preferences; triggers that create notifications on new messages/announcements and answered questions; realtime on notifications |
| `0011_verse_images.sql` | verse_images gallery; owner-only RLS |
| `0012_bible_search_tuning.sql` | phrase-substring boost in `search_bible` so a typed phrase (e.g. "lean not unto") sorts above stop-word/stem noise |

One migration per logical change, numbered sequentially. Never disable RLS.

### Pastoral guardrails encoded in RLS (`0006_chat.sql`)

The oversight model is deliberately narrow:

- **DMs** are read-only-overseen by the **house leader** of the pair (the chat
  carries the participants' shared house). The pastor cannot read, or even see
  the existence of, a DM; reported messages are the only path to DM content.
- **Discipler chats** are read-only-overseen by the **parish pastor**, not house
  leaders.
- Oversight is strictly read-only: an overseer may read but never post.
- `answer_question` surfaces answers through the **anonymized** `public_qa` view
  only; the raw `ask_questions` row (carrying `asker_id`) is never exposed to
  other members.

### A note on upserts against dated content

`devotionals` and `word_of_day` use **partial** unique indexes on
`(parish_id, publish_date) WHERE publish_date IS NOT NULL` (drafts may have a
null date). Any `ON CONFLICT` upsert must repeat the predicate:

```sql
insert into public.word_of_day (...) values (...)
on conflict (parish_id, publish_date) where publish_date is not null
do update set ...;
```

## RLS model

Policies call SECURITY DEFINER helpers so they can reference the caller's parish/
role without recursing on the protected tables:

- `current_profile_id()`, `current_parish_id()`, `current_house_id()`, `current_user_role()`, `is_parish_admin()`

Parish isolation is the backbone: members only ever see rows in their own parish.
Content is additionally gated on `status = 'published' AND publish_date <= today`,
except for admins who see drafts and scheduled items.

## Verifying without the full stack

When the Supabase CLI / Docker isn't handy (CI, quick checks), smoke-test every
migration against a plain Postgres:

```bash
# Point libpq at any Postgres you can create databases on, then:
PGPORT=5432 ./scripts/test-migrations.sh
```

It installs minimal Supabase `auth` stubs (`supabase/tests/auth_stubs.sql`:
`auth.users`, `auth.uid()`, and the `anon` / `authenticated` / `service_role`
roles), applies `0001 → 0009 → seed` in order, and fails on the first error. A
clean run confirms the schema builds, the seed loads (7 houses, 66 Bible books,
announcements + house chats), and the helper functions compile.

### RLS regression suite

`scripts/test-rls.sh` goes further: it builds the same stubbed DB, then switches
to the `authenticated` role with a JWT `sub` GUC and asserts the pastoral
guardrails (`supabase/tests/rls_test.sql`). 26 assertions cover DM/discipler
oversight (and that oversight is read-only), pastor-cannot-see-DM, parish
isolation, anonymized Ask-Pastor, prayer-wall house scoping, block-hides-messages,
notification fan-out, and Bible read access. Any violation aborts non-zero.

```bash
PGPORT=55432 ./scripts/test-rls.sh
```

This validates real RLS behaviour with `auth.uid()` resolving from the JWT claim,
so it is the fastest guard against a future migration regressing a guardrail.
The full stack (`supabase start`) remains the final check before deploy.

## Edge functions

Four Deno functions live in `supabase/functions/` (`send-push`,
`moderate-message`, `daily-content-publish`, `archive-term`). Two are wired to
Database Webhooks and two to a schedule; see `supabase/functions/README.md` for
triggers, secrets, and deploy steps.

## Bible data

`0003_bible.sql` seeds the KJV version row and all 66 book rows (order,
testament, abbreviation). Verse text is loaded separately so `supabase db reset`
stays fast: the dev `seed.sql` carries a tiny real-KJV sample (Psalm 23,
Proverbs 3:5-6, John 3:16).

The **full KJV** (1,189 chapters / 31,102 verses, public domain, from
scrollmapper/bible_databases) lives in `supabase/seed/kjv.sql`. Load it once
after a reset:

```bash
PGPORT=54322 ./scripts/load-kjv.sh        # or: psql ... -f supabase/seed/kjv.sql
```

It bulk-loads via a temp staging table + `COPY` (a couple of seconds), disabling
the per-row `verse_count` trigger during load and recomputing counts in one pass;
`search_vector` is maintained by its `BEFORE` trigger throughout. The load is
idempotent (`ON CONFLICT DO NOTHING`) and joins onto the seeded books by
canonical `book_order`, so it coexists with the dev sample.
