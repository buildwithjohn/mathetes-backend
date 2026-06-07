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

This stubbed harness validates schema + function definitions. Full RLS behaviour
(JWT-scoped `auth.uid()`, oversight visibility) is best verified against the real
stack via `supabase start`.

## Edge functions

Four Deno functions live in `supabase/functions/` (`send-push`,
`moderate-message`, `daily-content-publish`, `archive-term`). Two are wired to
Database Webhooks and two to a schedule; see `supabase/functions/README.md` for
triggers, secrets, and deploy steps.

## Bible data

`0003_bible.sql` seeds the KJV version row and all 66 book rows (order,
testament, abbreviation). Chapters and verse text are loaded separately: the dev
`seed.sql` includes a small, real-KJV sample (Psalm 23, Proverbs 3:5-6, John
3:16) sufficient to exercise `search_bible` / `get_chapter` / `parse_reference`.
The full 1,189-chapter / 31,102-verse import is a large data file (public-domain
source such as scrollmapper/bible_databases) loaded once into `bible_chapters` /
`bible_verses`; the `search_vector` and `verse_count` are maintained by triggers
on insert.
