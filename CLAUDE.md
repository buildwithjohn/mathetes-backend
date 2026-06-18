# Mathetes Backend

This is the Supabase project for Mathetes: database schema, migrations, RLS
policies, edge functions, and seed data.

## Project Overview

Mathetes serves CCCFSP FUOYE (one pilot parish, 7 house fellowships, ~100 to 150
disciples in Phase 1). The architecture is multi-tenant from day one: parishes
table exists, but UI exposes only one parish. When the second fellowship onboards
(post-launch), it's a configuration change, not a rebuild.

## Tech Stack

- **Database:** Supabase Postgres
- **Auth:** Supabase Auth
- **Storage:** Supabase Storage (profile pics, devotional images, verse images)
- **Real-time:** Supabase Realtime (chat)
- **Edge Functions:** Deno runtime (cron jobs, push notification triggers,
  moderation hooks)
- **CLI:** Supabase CLI for migrations

## Schema Overview

Core tables (canonical list):

**Identity & structure:**
- parishes (id, name, abbr, campus_name, network_id)
- houses (id, parish_id, slug, name, color, verse, verse_ref, leader_id)
- user_profiles (id, auth_id, parish_id, house_id, name, photo_url, role,
  year, dept, pinned_verse_ref, joined_at)
- user_privacy (user_id, photo_visibility, dm_who, cross_gender_dm_approval,
  mentions_notify)

**Content:**
- devotionals (id, parish_id, title, body_md, scripture_refs, publish_date,
  author_id, series_id, status)
- devotional_series (id, parish_id, title, total_days)
- word_of_day (id, parish_id, verse_ref, verse_text, reflection, publish_date,
  author_id, status)
- announcements (id, parish_id, title, body, event_data, banner, photos,
  posted_at, posted_by)

**Bible:**
- bible_versions, bible_books, bible_chapters, bible_verses

**Personal library:**
- bookmarks, highlights, notes, reading_position

**Engagement:**
- streaks, engagement_events

**Chat:**
- chats (kinds: house_group, announcements, ask_pastor, discipler, dm)
- chat_members, messages, message_reactions, pinned_messages

**Prayer wall:** prayer_requests, prayer_pray, prayer_reactions

**Ask Pastor:** ask_questions

**Notifications:** push_tokens, notifications, notification_preferences

**Safety:** blocks, reports, moderation_log

**Verse images:** verse_images

## RLS Policies (Critical)

Every table has RLS enabled. Policies enforce:

1. User can read/write their own data (notes, bookmarks, highlights, etc.)
2. Parish isolation: users only see content in their parish
3. House isolation: house-scoped content limited to members
4. DM access: only the sender and receiver. Private DMs are NOT a passive
   oversight surface (0029) — leaders/pastors cannot browse them. A reported DM
   message becomes visible to parish admin/pastor for that one message only.
5. Discipler chat: disciple, discipler, and parish pastor (oversight)
6. Admin access: role='pastor' or 'admin' can manage parish content
7. Public content: WOTD, devotionals, announcements readable by parish members
8. Bible: readable by all authenticated users

## Coding Conventions

- One migration per logical change.
- Migrations numbered sequentially (0001, 0002, ...).
- Never disable RLS in production.
- Use database triggers for derived data (streak updates, notification creation).
- Generate types after each migration: `./scripts/generate-types.sh`.

## Edge Functions

- `send-push`: triggered by inserts on `notifications`. Sends Expo push.
- `moderate-message`: triggered by inserts on `messages`. Runs OpenAI moderation.
- `daily-content-publish`: cron at 00:01 UTC. Publishes scheduled content.
- `archive-term`: cron at end of academic term. Archives chat history.

## Reference

- /supabase/migrations/ for schema history
- /docs/data-model.md for entity-relationship notes
