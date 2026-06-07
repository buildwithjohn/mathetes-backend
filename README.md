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

One migration per logical change, numbered sequentially. Never disable RLS.

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

The migrations are smoke-tested against Postgres via PGlite (no Docker needed).
See the project root notes; in short, applying `0001 → 0002 → seed` yields 7
seeded houses, an auto-created profile/privacy row on `auth.users` insert, and
resolvable `todays_*` views.

## Next migrations (planned)

`0003_bible.sql` (KJV import + full-text search), `0004_chat.sql`,
`0005_prayer_wall.sql`, `0006_safety.sql`, `0007_notifications.sql`.
