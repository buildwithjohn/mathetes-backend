# Mathetes Data Model

Entity notes and relationships. Filled in as the schema grows.

## Migration history

| Migration | Adds |
|-----------|------|
| 0001_init_identity.sql | parishes, houses, user_profiles, user_privacy, handle_new_user trigger, CCCFSP FUOYE seed (7 houses) |
| 0002_content.sql | devotional_series, devotionals, word_of_day, content_assets, today views |
| 0003_bible.sql | bible_versions/books/chapters/verses, full-text search, search_bible/get_chapter/parse_reference, KJV + 66 books |
| 0004_personal_library.sql | notes, bookmarks, highlights, reading_position |
| 0005_engagement.sql | streaks (grace-day), engagement_events, record_check_in |
| 0006_chat.sql | chats, chat_members, messages, message_reactions, pinned_messages, discipler_id, oversight RLS, create_dm |
| 0007_prayer_wall.sql | prayer_requests, prayer_pray, prayer_reactions |
| 0008_ask_pastor.sql | ask_questions, answer_question, public_qa view |
| 0009_safety.sql | blocks, reports, moderation_log |
| 0010_notifications.sql | push_tokens, notifications, notification_preferences, message/answer notify triggers |
| 0011_verse_images.sql | verse_images |
| 0012_bible_search_tuning.sql | search_bible phrase-substring boost |
| 0013_storage.sql | storage buckets + storage.objects RLS (own-folder writes) |
| 0014_announcements.sql | announcements content table + publish→notify trigger |
| 0015_chat_media.sql | chat-media storage bucket (+ avatars made public) |
| 0016_campuses.sql | campuses table + user_profiles.campus_id (FUOYE Oye + Ikole) |
| 0017_parish_chat.sql | parish_group chat kind (parish-wide general room) |
| 0018_campus_houses.sql | houses.campus_id (Oye + Ikole houses), user_profiles date_of_birth/phone |

Bible verse text: dev sample in `seed.sql`; full KJV (31,102 verses) in
`supabase/seed/kjv.sql`, loaded via `scripts/load-kjv.sh`.

## Identity & structure

```
parishes 1 ──< houses
parishes 1 ──< user_profiles >── houses
user_profiles 1 ──1 user_privacy
houses.leader_id ──> user_profiles.id  (set after profiles exist)
```

- A **parish** is a campus fellowship (pilot: CCCFSP FUOYE).
- A **house** is a sub-fellowship within a parish (7 in the pilot).
- A **user_profile** belongs to one parish and one house. Created automatically
  by the `handle_new_user` trigger when an auth user is inserted.
- **user_privacy** holds per-user privacy defaults (conservative by design).

### Roles
`member` < `discipler` < `house_leader` < `pastor` / `admin`

## Content

```
parishes 1 ──< devotional_series 1 ──< devotionals
parishes 1 ──< word_of_day
devotionals 1 ──< content_assets >── word_of_day
```

- **devotionals** and **word_of_day** are parish-scoped, status-gated
  (`draft` / `scheduled` / `published`) and dated by `publish_date`.
- One WOTD and one devotional per parish per day (unique constraint).
- Views `todays_word_of_day` / `todays_devotional` resolve "today" per parish.

## Bible

```
bible_versions 1 ──< bible_books 1 ──< bible_chapters 1 ──< bible_verses
```

- KJV only at MVP. Readable by every authenticated user; never user-writable.
- `bible_verses.search_vector` (tsvector, GIN-indexed) powers `search_bible`.
- `bible_chapters.verse_count` is maintained by trigger as verses load.
- Helpers: `search_bible(query, version_code)`, `get_chapter(version_code,
  book_abbrev, n)` (returns jsonb), `parse_reference('John 3:16')`.

## Personal library

```
user_profiles 1 ──< notes / bookmarks / highlights
user_profiles 1 ──1 reading_position
highlights >── notes (optional)   highlights/bookmarks >── bible_verses
```

- Strictly private: every row is owned by one profile; RLS allows only the owner.
- One highlight and one bookmark per (user, verse). `highlights.color` is a fixed
  palette.

## Engagement

```
user_profiles 1 ──1 streaks
user_profiles 1 ──< engagement_events
```

- `record_check_in()` is idempotent per day and bridges a single missed day with
  one **grace day per calendar month**; a 2+ day gap (grace spent) resets to 1.
- `engagement_events` is the analytics log; owner reads own, parish admins read
  events for members of their parish.

## Chat (pastoral oversight)

```
parishes 1 ──< chats >── houses (house_group / dm)
chats 1 ──< chat_members >── user_profiles
chats 1 ──< messages 1 ──< message_reactions
chats 1 ──< pinned_messages
user_profiles.discipler_id ──> user_profiles.id
```

- Kinds: `house_group`, `announcements`, `ask_pastor_thread`, `discipler`, `dm`.
- **Oversight (read-only):** DM → house leader of the pair; discipler chat →
  parish pastor. No blanket pastor/admin read of private chats.
- Automation: assigning a `house_id` auto-joins the house group chat (leaders get
  the `leader` role); setting `discipler_id` creates the discipler chat. `create_dm`
  opens/reuses a DM (carrying the shared house for oversight).
- `messages` and `message_reactions` are published to `supabase_realtime`.

## Prayer wall

```
parishes/houses ──< prayer_requests 1 ──< prayer_pray / prayer_reactions
```

- `house_id` null = parish-wide; otherwise scoped to that house. House leaders
  (and parish admins) see every request in their house, including `anonymous`
  ones (identity is hidden in the UI, not from pastoral care).

## Ask Pastor

```
parishes ──< ask_questions  ─(answered & public)→ public_qa (view, anonymized)
```

- A queue, not a chat. `answer_question(id, response, public?)` (pastor/admin)
  sets the answer and privacy. Public answers are exposed only through the
  anonymized, parish-scoped `public_qa` view; `asker_id` never leaks.

## Safety

```
user_profiles ──< blocks >── user_profiles
parishes ──< reports >── user_profiles (reporter/resolver)
messages ──< moderation_log
```

- A **block** is enforced at the row level: a RESTRICTIVE policy hides the
  blocked user's `messages` from the blocker.
- `reports` are filed by members, read/resolved by parish admins.
- `moderation_log` is written by the `moderate-message` edge function (service
  role) and read by parish admins.

## Notifications

```
user_profiles 1 ──< push_tokens
user_profiles 1 ──< notifications
user_profiles 1 ──< notification_preferences
```

- In-app `notifications` rows are created by SECURITY DEFINER triggers
  (`notify_on_message`, `notify_on_answer`) and the `daily-content-publish` job,
  never directly by a member. Owners read/mark-read/delete their own.
- `notify_on_message` fans out to other chat members (skipping the author and
  muted members); for the announcements channel it fans out to the whole parish.
- The `send-push` edge function turns a new notification row into an Expo push,
  consulting the per-type `push` preference. `notifications` is published to
  realtime for the live bell.

## Verse images

```
user_profiles 1 ──< verse_images
```

- A private gallery row per generated image (theme, aspect_ratio, watermark,
  url). Images themselves live in the public `verse-images` storage bucket.

## Realtime publication (Finding B4)

Chat and notifications rely on the `supabase_realtime` publication including
`public.messages`, `public.message_reactions`, `public.chat_members`, and
`public.notifications`. Migrations 0006 and 0010 add these, but the `ALTER
PUBLICATION` is wrapped in a tolerant block: on hosted Supabase the publication
is owned by another role, so a permission error is swallowed with a NOTICE
rather than aborting the migration. That means on cloud the tables may silently
not get added.

**Verify (run against the cloud DB):**

```sql
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
order by tablename;
```

Expected: `messages`, `message_reactions`, `chat_members`, `notifications`
(all in `public`).

**Manual fix if any are missing:** Supabase Dashboard → **Database →
Replication** → the `supabase_realtime` publication → enable the missing
table(s). Equivalent SQL (run as the publication owner / via the dashboard):

```sql
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_reactions;
alter publication supabase_realtime add table public.chat_members;
alter publication supabase_realtime add table public.notifications;
```

Without these, the mobile app's live chat and notification bell fall back to
manual refresh (data is correct, just not pushed in real time).

## Reading plans (V2.0)

```
parishes 1 ──< reading_plans 1 ──< reading_plan_days
user_profiles 1 ──< reading_plan_subscriptions >── reading_plans
reading_plan_subscriptions 1 ──< reading_plan_progress >── reading_plan_days
```

- A **reading_plan** is a parish-authored, multi-day scripture + reflection
  journey (`length_days` 1–365, `difficulty` starter/intermediate/deep,
  `sequence_locked`, `published`). Admin-authored only; members read only
  `published` plans in their parish.
- **reading_plan_days** carry the day's passage, reflection body, and prompt
  (optionally linked to a `devotional`). Visible when the parent plan is
  published in the member's parish (admins see drafts too).
- **reading_plan_subscriptions** are per (user, plan): `current_day`, `paused`
  (pastoral grace — a first-class state), `streak_enabled` (opt-in, default
  off), `completed_at`. Owner-managed; admins may see that a subscription
  exists (support/analytics) but never the reflections.
- **reading_plan_progress** records per-day completion + the user's
  `reflection_response`. **Reflections are private by default.** A row may be
  shared with the subscriber's **discipler** (and only the discipler) via
  `share_with_discipler`; there is no policy path for a house leader or
  pastor/admin to read reflections, and no public completion data or
  leaderboards.

RPCs: `subscribe_to_plan(plan)` (idempotent; refuses unpublished/out-of-parish),
`complete_plan_day(day, reflection?, share?)` (records progress, advances the
subscription, completes on the last day), `toggle_plan_pause(subscription)`.
Discipler visibility is enforced via SECURITY DEFINER helpers
`owns_plan_subscription` / `is_discipler_for_subscription`.
