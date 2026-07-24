# Mathetes Backend — CONTEXT (source of truth)

The backend's own source of truth. Keep it current as the contract evolves.
Cross-repo master doc: `mathetes-mobile/docs/WORKSPACE.md` (authoritative for the
whole workspace — stay consistent with it; this file owns the backend detail).

> Note: `mathetes-mobile/docs/WORKSPACE.md` is the cross-repo master and owns the
> shared role/gating model (its §4, incl. the 0033 leader-reach decision). It
> lives on the mobile `dev` branch; this file stays consistent with it and owns
> the backend detail.

---

## 1. Overview & layout

Mathetes is a Supabase project (Postgres + Auth + Storage + Realtime + Deno edge
functions) serving the **CCCFSP FUOYE** pilot parish (one parish, two campuses —
Oye + Ikole — 7 house fellowships per campus). Multi-tenant from day one
(`parishes` exists) but the UI exposes a single parish.

```
supabase/
  migrations/   0001..0032  — append-only, numbered, idempotent SQL
  functions/    Deno edge functions (send-push, moderate-message,
                daily-content-publish, archive-term, paystack-*)
  seed.sql      tiny dev seed (sample Bible verses etc.)
  seed/         full Bible text: kjv.sql, web.sql, bsb.sql, asv.sql (~4 MB each)
  tests/        auth_stubs.sql + rls_test.sql (80 RLS assertions)
scripts/        test-migrations.sh, test-rls.sh, test-kjv.sh, test-bible.sh,
                load-kjv.sh, load-bible.sh, gen_bible_seed.py, generate-types.sh
types/database.types.ts   canonical TS types (mobile + admin mirror this)
docs/           CONTEXT.md (this), data-model.md, HANDOFF.md
```

**Cloud project:** ref `jowokfnlfqqjzwhvnmxj`, region `eu-west-1`.

### How migrations reach prod
The sandbox/agent cannot reach the cloud Postgres (only HTTPS egress), so
migrations are applied **out-of-band by the operator**:
- Small migrations: paste the SQL into the **Supabase SQL editor** and run.
- Large data loads (full Bible seeds use `COPY … FROM stdin`): run with **`psql`**
  (e.g. `./scripts/load-bible.sh web bsb asv`) — the editor can't run `COPY`.
- Every migration is **idempotent** (`create … if not exists`, `create or
  replace`, `drop policy if exists`, `on conflict do nothing`) — safe to re-run.

**Repo HEAD: migration `0046`.** Prod is applied piecemeal; confirm what's live:
```sql
select version, name from supabase_migrations.schema_migrations order by version;
-- or, if the schema_migrations table isn't populated (applied via editor),
-- spot-check the objects (e.g. select 1 from public.library_items limit 0;).
```

### Build / test locally
`./scripts/test-migrations.sh` (apply all + seed), `./scripts/test-rls.sh` (80
guardrail assertions), `./scripts/test-kjv.sh`, `./scripts/test-bible.sh`. CI
(`.github/workflows/ci.yml`) runs all four on every push/PR.

---

## 2. Migration history (one line each)

| # | File | Adds |
|---|------|------|
| 0001 | init_identity | `parishes`, `houses`, `user_profiles`, `user_privacy`; `handle_new_user` trigger; helper fns (`current_profile_id/parish_id/house_id/user_role`, `is_parish_admin`); CCCFSP seed |
| 0002 | content | `devotionals`, `word_of_day`, `devotional_series`, content assets; `todays_devotional`/`todays_word_of_day` views; `set_updated_at` |
| 0003 | bible | `bible_versions/books/chapters/verses` + FTS; `search_bible`, `get_chapter`, `parse_reference`; seeds KJV version + 66 books |
| 0004 | personal_library | `bookmarks`, `highlights`, `notes`, `reading_position` (strictly per-user) |
| 0005 | engagement | `streaks` (one grace day/month), `engagement_events`; `record_check_in` |
| 0006 | chat | `chats`, `chat_members`, `messages`, `message_reactions`, `pinned_messages`; oversight RLS; `can_read_chat`/`can_post_chat`/`is_chat_member`/`is_chat_leader`; `create_dm`; realtime on messages/reactions/chat_members |
| 0007 | prayer_wall | `prayer_requests`, `prayer_pray`, `prayer_reactions`; `can_read_prayer` |
| 0008 | ask_pastor | `ask_questions` queue; `answer_question`; anonymized `public_qa` view |
| 0009 | safety | `blocks`, `reports`, `moderation_log`; block-hides-messages (restrictive RLS); `is_blocked_by_me` |
| 0010 | notifications | `push_tokens`, `notifications`, `notification_preferences`; `notify_on_message`/`notify_on_answer` triggers; realtime on notifications |
| 0011 | verse_images | `verse_images` gallery + `verse-images` public bucket |
| 0012 | bible_search_tuning | phrase-substring boost in `search_bible` |
| 0013 | storage | `avatars` + `devotional-images` buckets and own-folder write RLS |
| 0014 | announcements | `announcements` content table + publish→notify trigger (`notify_on_announcement`) |
| 0015 | chat_media | `chat-media` bucket; makes `avatars` public |
| 0016 | campuses | `campuses` table + `user_profiles.campus_id` (Oye/Ikole) |
| 0017 | parish_chat | `parish_group` chat kind (read+write by all parish members) |
| 0018 | campus_houses | `houses.campus_id` (7 houses/campus = 14); member `date_of_birth`/`phone` |
| 0019 | content_media | `devotionals.video_url` + `content-media` bucket |
| 0020 | cross_gender_dm | Finding B2: cross-gender DM approval gate in `create_dm` |
| 0021 | cross_house_dm | Finding B1: DMs must share a non-null house (authoritative `create_dm`) |
| 0022 | reading_plans | `reading_plans/_days/_subscriptions/_progress`; `subscribe_to_plan`, `complete_plan_day`, `toggle_plan_pause`; reflection-privacy RLS |
| 0023 | giving | `giving_funds`, `giving_recurring`, `donations`, `paystack_events` (kobo; Paystack); finance-admin RLS |
| 0024 | giving_realtime | realtime on `donations` + `giving_recurring`; (init returns `access_code`) |
| 0025 | membership_gating | `user_profiles.status`, `campuses.allowed_email_domains`; `is_active_member`; **self-escalation guard** (`guard_profile_protected_cols`); domain auto-approve in `handle_new_user`; `approve_member`/`reject_member` |
| 0026 | set_my_campus | `set_my_campus` RPC (member picks own campus once, in-parish) |
| 0027 | oversight | admin pending-select policy; `list_pending_members`; `resolve_report` |
| 0028 | owner_and_admin_actions | `user_profiles.is_owner` + `is_owner()`; approve/reject/resolve narrowed to `role='admin'`; owner-only-grants-admin; `answer_question` re-answer guard |
| 0029 | dm_no_passive_oversight | **removes** house-leader passive DM read; adds report-only DM message exposure (`messages_select_reported`) |
| 0030 | more_bible_versions | WEB + BSB + ASV version rows + 66 books each (text in `seed/{web,bsb,asv}.sql`) |
| 0031 | library | `library_items` (books/manuals/audio/video) + RLS; widens `content-media` (PDF/images, 512 MB) |
| 0032 | wotd_prayer | `word_of_day.prayer_md` (optional "Pray" markdown); recreates `todays_word_of_day` |
| 0033 | leader_reach | **role-aware leader reach**: parish admins see the whole-parish directory (`user_profiles_select_leader_directory`); `create_dm` lets owner/pastor/admin DM any active parish member (cross-house + cross-gender bypassed) and lets a member DM their own disciples (discipler_id pointer); students unchanged |
| 0034 | open_dms | **fully open DMs** (John's decision): `create_dm` lets ANY active member DM any other active parish member; removes the cross-house (B1) and cross-gender-approval (B2) gates entirely (supersedes 0033's create_dm). Kept: same parish + active target. Oversight unchanged (0029) |
| 0035 | content_reliability | durable devotional bookmarks; date-safe publishing; notification delivery hardening |
| 0036 | content_covers | editorial cover-image columns for Word and devotional content |
| 0037 | word_notes | private reflections attached to a Word of the Day |
| 0038 | formation_practices | private rhythm activities + Scripture collections; opt-in House Quests/Campus Missions; Fellowship Events + private RSVPs; answered-prayer markers; no public scores or leaderboards |
| 0039 | member_deletions | durable service-role audit snapshots for intentional member-account deletions |
| 0040 | notification_delivery | devotional + immediately-published Word notification fan-out; adds `devotional` notification type |
| 0041 | push_webhook_delivery | secure, database-owned `notifications` → `send-push` pg_net delivery trigger (Vault/Edge shared secret) |
| 0042 | lagos_content_notifications | fixes scheduled content notification fan-out at the UTC/Lagos day boundary; backfills only today's missed devotional notification |
| 0043 | message_notification_sender | message and announcement notifications identify the sender by display name (recipient already has chat access) |
| 0044 | content_audio_uploads | accepts M4A/WebM browser MIME variants in the pastor/admin `content-media` narration bucket |
| 0045 | circles_and_prayer_meetings | private student-created Circle chats, editable membership/photo/roles, and LiveKit audio/video prayer rooms |
| 0046 | circle_recordings | host-controlled Circle teaching recordings, private R2 media, status/audit metadata, Circle-only RLS and realtime |
| 0047 | member_profile_presence | optional member bio and current thought, constrained to existing active-parish profile visibility |
| 0048 | content_signals | parish-visible live Amen/share totals for published daily Word and devotionals; each member contributes once, identities remain private, no rankings |
| 0049 | saved_daily_content | durable Word bookmarks and private devotional reflections, both restricted to the member and already-visible parish content |
| 0050 | formation_badges | private, idempotent formation milestones awarded from activity logging; no public scores, leaderboards, or member-to-member visibility |
| 0052 | group_stewardship | global owner may steward same-parish shared House/parish groups and Circles (never DMs/discipler/Ask-Pastor); canonical `assign_house_members` RPC for House roster management |

---

## 3. Security model (critical)

RLS is enabled on every table; access is governed by policies, not by withheld
grants. Core principles:

- **Parish isolation** — content/chat scoped to the caller's parish via
  `current_parish_id()`. **House isolation** for house-scoped content.
- **Directory visibility (`user_profiles` SELECT)** — any **active** member sees
  active parish-mates (0025; self always visible). Parish **admins** additionally
  see every in-parish profile of any status (0033 `user_profiles_select_leader_directory`)
  plus null-parish pending signups (0027). Pending/suspended/rejected stay hidden
  from students. `photo_visibility` is honoured in the app layer, not RLS (RLS is
  row-level; the column is always returned).
- **Self-escalation guard (0025/0028)** — a `BEFORE UPDATE` trigger
  (`guard_profile_protected_cols`, SECURITY INVOKER) blocks any client change to
  `role`, `status`, `parish_id`, `campus_id`, or `is_owner`. Only a parish admin
  (or a privileged DB role inside a SECURITY DEFINER RPC) may change them; and
  granting/removing **admin** or **ownership** requires an **owner**. A client
  can never make itself an admin. Verify this — it is the heart of the model.
- **Identity resolution** — the helper functions are all SECURITY DEFINER,
  `stable`, and resolve off **`user_profiles.auth_id = auth.uid()`**:
  `current_profile_id()` → profile id, `current_parish_id()`, `current_house_id()`,
  `current_user_role()`, `is_parish_admin()` (role in pastor/admin),
  `is_owner()` (role='admin' AND is_owner), `is_active_member()` (status='active').
- **Chat gating** — `can_read_chat(chat)` / `can_post_chat(chat)` (SECURITY
  DEFINER) require an **active** member and encode who may read/post per chat
  kind. Members read/post their own house/parish/DM/discipler chats; admins read
  ask-pastor threads; pastor reads discipler chats (oversight).
- **Pastoral oversight = activity, not surveillance** — leaders see that members
  are engaging and can act on **reports**, but do not browse private content:
  - **DMs (0029):** readable only by the two participants. House leaders/pastors
    have **no** passive DM read. A **reported** DM message is exposed to parish
    admin/pastor for that one message only (`messages_select_reported`).
    - **DM initiation is role-aware (0033)** but oversight is **unchanged**:
      `create_dm` lets leaders (owner/pastor/admin, and a member toward their own
      disciples) *start* a cross-house/cross-gender DM for pastoral care. It does
      not grant any new read path — a leader still can't browse DMs they aren't a
      party to. After 0029 `chat.house_id` no longer drives DM access, so a
      cross-house leader DM (house_id null) is fully readable by its two members.
  - **Discipler chats:** pastor has read-only oversight (accountability surface).
  - **Reading-plan reflections:** private; optionally shared with the
    subscriber's discipler only; no pastor/leader/admin path; no leaderboards.
  - **Giving:** a giver sees only their own; finance admins see parish records;
    no public donor lists.
  - **Ask-pastor public answers:** anonymized via `public_qa`; `asker_id` never
    leaks.
  - **Blocks:** a restrictive policy hides a blocked user's messages from the
    blocker.

---

## 4. Functions & RPCs

### Identity / gating helpers (SECURITY DEFINER, stable)
`current_profile_id()→uuid`, `current_parish_id()→uuid`, `current_house_id()→uuid`,
`current_user_role()→text`, `is_parish_admin()→bool` (pastor|admin),
`is_owner()→bool`, `is_active_member()→bool`, `is_blocked_by_me(p_target uuid)→bool`,
`can_read_chat(p_chat uuid)→bool`, `can_post_chat(p_chat uuid)→bool`,
`is_chat_member(p_chat uuid)→bool`, `is_chat_leader(p_chat uuid)→bool`,
`can_read_prayer(p_request uuid)→bool`, `owns_plan_subscription(p_sub uuid)→bool`,
`is_discipler_for_subscription(p_sub uuid)→bool`. (Used inside RLS — not meant as
app calls.)

### Callable RPCs

| RPC | Args | Returns | Who may call |
|-----|------|---------|--------------|
| `set_my_campus` | `p_campus uuid` | `void` | Any authenticated member whose own `campus_id` is null; sets it **once**, only to a campus in their own parish |
| `approve_member` | `p_user uuid, p_campus uuid` | `void` | **admin only** (`role='admin'`, incl. owner) — pastors cannot (0028). Activates a pending user into a campus in the caller's parish |
| `reject_member` | `p_user uuid` | `void` | **admin only** (0028). Sets `status='rejected'` |
| `list_pending_members` | — | `table(id, name, email, created_at)` | `is_parish_admin()` (pastor + admin). Pending queue with email (auth.users isn't client-readable) |
| `resolve_report` | `p_report uuid, p_status text` | `void` | **admin only** (0028). `p_status ∈ {reviewing,resolved,dismissed}`; parish-scoped; stamps resolver + time |
| `answer_question` | `p_id text, p_response text, p_public boolean=false` | `ask_questions` | `is_parish_admin()` (pastor + admin). **Re-answer-guarded**: only an `awaiting` question can be answered (0028) |
| `create_dm` | `p_other uuid` | `uuid` (chat id) | **Fully open (0034).** Any active member may DM any other **active** member in the **same parish**. No house or cross-gender gate (both removed; supersedes 0033's role-aware version). Idempotent (reuses existing DM, never re-gated). Oversight unchanged (0029: DMs private to participants) |
| `subscribe_to_plan` | `p_plan_id uuid` | `uuid` (subscription id) | Active member. Refuses unpublished / out-of-parish plans; idempotent |
| `complete_plan_day` | `p_day_id uuid, p_reflection_response text=null, p_share_with_discipler boolean=false` | `uuid` | Subscription owner. Records progress, advances `current_day`, completes on last day |
| `toggle_plan_pause` | `p_subscription_id uuid` | `boolean` (new paused state) | Subscription owner |
| `record_check_in` | — | `streaks` | Caller. Idempotent per day; bridges one missed day via a monthly grace day |
| `get_chapter` | `version_code text, book_abbrev text, chapter_number int` | `jsonb` | Any authenticated user (Bible is world-readable). Version-aware |
| `search_bible` | `query text, version_code text='KJV', max_results int=50` | `table(verse_id, reference, …, rank)` | Any authenticated user. Version-scoped, websearch grammar |
| `parse_reference` | `ref text, version_code text='KJV'` | `table(book_id, book_name, chapter, verse)` | Any authenticated user |

### Triggers (not callable)
`handle_new_user` (signup → profile + privacy, domain auto-approve, role always
`member`), `guard_profile_protected_cols` (self-escalation guard),
`set_updated_at`, `notify_on_message`/`notify_on_answer`/`notify_on_announcement`/
`notify_on_devotional`/`notify_on_word_of_day`,
`sync_house_chat_membership`, `sync_discipler_chat`,
`bible_verses_search_vector`, `bible_sync_verse_count`.

---

## 5. Edge functions (Deno)

**Not deployed yet** for giving (Paystack account pending). The webhook/cron
functions are written but must be deployed + wired per environment (they live
outside the migration chain by design — they depend on `pg_net`/`pg_cron`).

| Function | Trigger | Contract |
|----------|---------|----------|
| `send-push` | `trg_queue_push_delivery`: INSERT on `notifications` → secure `pg_net` call | Sends Expo push to recipient `push_tokens`, honours per-type pref, prunes dead tokens. Requires matching Edge `SEND_PUSH_WEBHOOK_SECRET` + Vault `mathetes_send_push_webhook` |
| `moderate-message` | Webhook: INSERT on `messages` | OpenAI moderation; soft-deletes flagged messages, writes `moderation_log` |
| `daily-content-publish` | Cron `1 0 * * *` | Publishes scheduled WOTD/devotionals using the Africa/Lagos date; content triggers fan out both Word and devotional notifications |
| `archive-term` | Cron daily | Soft-archives house/discipler/DM messages `ARCHIVE_AFTER_DAYS` after `TERM_END_DATE` (dry-run unless `ARCHIVE_CONFIRM=true`) |
| `paystack-initialize` | User call (JWT) | **Body** `{ amount_kobo:int>0, kind:'one_time'\|'recurring', fund_id?, interval?, anonymous?, note?, callback_url? }`. Creates a PENDING `donation` (one-time) or a `giving_recurring` mandate + Paystack plan, calls Paystack `/transaction/initialize`. **Returns** `{ authorization_url, access_code, reference }` |
| `paystack-webhook` | Paystack (no JWT) | Verifies `x-paystack-signature` (HMAC-SHA512); logs every event to `paystack_events`; records `charge.success` / `subscription.create` / `invoice.payment_failed` / `subscription.disable` idempotently |
| `paystack-manage-recurring` | User call (JWT) | **Body** `{ recurring_id, action:'cancel'\|'pause'\|'resume' }`; ownership-checked; toggles the Paystack subscription |

**Secrets** (`supabase secrets set`): `OPENAI_API_KEY` (moderate-message),
`PAYSTACK_SECRET_KEY` (paystack-*), `TERM_END_DATE`/`ARCHIVE_AFTER_DAYS`/
`ARCHIVE_CONFIRM` (archive-term). `SUPABASE_URL`/`SERVICE_ROLE_KEY`/`ANON_KEY`
auto-injected. `config.toml` sets `verify_jwt=false` for the webhook/cron four.
The client holds only the Paystack **public** key + the returned checkout URL.

---

## 6. Realtime & storage

**Realtime publication `supabase_realtime`** (added via tolerant DO-blocks —
verify on cloud, see `data-model.md` §Realtime): `messages`, `message_reactions`,
`chat_members` (0006), `notifications` (0010), `donations`, `giving_recurring`
(0024).

**Storage buckets** (all `public=true`, read-by-URL; writes gated by RLS):

| Bucket | Write access | Holds |
|--------|--------------|-------|
| `avatars` | own folder (`<profile>/…`) | profile photos |
| `devotional-images` | pastor/admin | devotional/WOTD images |
| `verse-images` | own folder | generated verse images |
| `chat-media` | own folder (`<auth.uid>/…`) | message images / voice notes |
| `content-media` | pastor/admin | devotional audio/video **and** Library files (PDF/audio/video/covers); 512 MB limit, MIME-restricted (0031; M4A/WebM variants in 0044) |

---

## 7. Cross-repo contracts the backend owns

- **Student gating** — `user_profiles.status ∈ {pending,active,rejected,suspended}`;
  signup auto-activates only if the email domain is in some
  `campuses.allowed_email_domains` (else `pending`). ⚠️ **`allowed_email_domains`
  must be seeded** (e.g. `fuoye.edu.ng`) or every signup falls to `pending`. The
  app shows a "pending approval" screen unless `status==='active'`.
- **Roles** — `member | discipler | house_leader | pastor | admin`; ownership is
  `role='admin' AND is_owner=true` (no separate enum). Only an owner grants admin.
- **Reading-plan guardrails** — reflections private; discipler-share opt-in only;
  no leaderboards.
- **Giving** — amounts in **kobo**; `donations.status ∈
  {pending,success,failed,abandoned,reversed}`; `giving_recurring.status ∈
  {pending,active,paused,attention,cancelled}`. All writes server-mediated (edge
  functions, service role) — members
  have no INSERT/UPDATE. **Open decision:** pastor visibility — finance admins
  currently see *individual* parish donations; if the parish wants pastors blind
  to who-gave-what (aggregate only), that's a policy change.
- **Bible translations** — KJV, WEB, BSB, ASV are public-domain and live.
  **NKJV/NLT are copyrighted** — do not import without a publisher licence or a
  licensed Bible API.
- **DM oversight (0029, resolved)** — the earlier "0028 decision" on tightening
  house-leader DM oversight was settled: passive DM reading is **removed
  entirely** (not merely existence-only); content surfaces only via a report.

---

## 8. Consumers (keep backward-compatible)

- **mobile** mirrors `types/database.types.ts` (copied into
  `mathetes-mobile/src/lib/database.types.ts`).
- **admin** writes via the RPCs above and the content tables.
- Therefore **any schema change must**: (1) be an append-only idempotent
  migration, (2) regenerate `types/database.types.ts` (and propagate), (3) stay
  backward-compatible (don't drop/rename columns the apps read; views built on
  `select *` must be recreated so new columns flow through — see 0032),
  (4) keep the RLS suite green.

---

## 9. Outstanding backend tasks

Operator / decision items (most code work through 0032 is done):

1. **Apply pending migrations to prod** — confirm `0028`–`0032` are all live
   (run the `schema_migrations` / spot-check query in §1). Load the new Bible
   text on prod if not yet done: `./scripts/load-bible.sh web bsb asv`.
2. **Seed `campuses.allowed_email_domains`** (FUOYE domains) — until then all
   signups land in `pending`. John's call.
3. **Email confirmation ON/OFF** for the pilot (affects signup → onboarding flow).
4. **Deploy edge functions** — `send-push`, `moderate-message`,
   `daily-content-publish`, `archive-term` (+ wire webhooks/cron); and the
   `paystack-*` trio once the **Paystack account** exists (+ set
   `PAYSTACK_SECRET_KEY`, register the webhook URL).
5. **Giving pastor-visibility decision** (see §7) — aggregate-only vs per-gift.
6. **Rotate secrets** exposed in chat: the **DB password** and the **GitHub PAT**.
7. **Authoritative type regen** via the Supabase CLI (`supabase gen types …`)
   when convenient, to replace the introspection-bootstrapped file.
8. **Reading-plan content** — the seeded plan ships 30 *placeholder* days; real
   devotional content TBD.
9. *(Optional, offered)* default-translation preference so a user's Bible choice
   persists; placeholder Library items for first render.

### 0035 reliability contract

- Due `scheduled` devotionals/WOTD are readable on their publish date even if
  the external cron is late; future scheduled content remains hidden. Writes
  scheduled for today/past are promoted immediately by a database trigger.
- Devotional saves persist in `devotional_bookmarks` and are private to the
  member under RLS.
- Message inserts already create `notifications` rows; the notification title is
  the sender's display name (0043) so both the in-app inbox and push alert make
  clear who wrote. Remote delivery still
  requires the production Database Webhook (`notifications` INSERT →
  `send-push`) and Expo/FCM credentials. `send-push` uses `target_url`, matching
  mobile deep-link handling, and Android high-priority delivery.
- `daily-content-publish` uses the Africa/Lagos calendar date. The cron remains
  useful for status promotion and morning notifications, but is no longer a
  content-availability dependency.
- **Production cron:** run `scripts/cloud_enable_daily_publisher.sql` once in
  Supabase SQL Editor. It invokes `daily-content-publish` at **00:01 WAT**
  (23:01 UTC) every day. This is an operator script rather than a normal
  migration because pg_cron/pg_net are managed Supabase extensions and are not
  available in the lightweight local RLS test database.

### 0045 Circles and private prayer meetings

- **Circles** are private, student-created parish groups implemented on the
  existing `chats` + `chat_members` contract (`kind='circle'`), with editable
  title/description/photo and explicit `owner` / `admin` member roles. The
  SECURITY DEFINER RPCs validate active same-parish invitees; they do not widen
  a parish admin's ability to browse private DMs or Circle content.
- `circle_meetings` is the invitation and permission record for ephemeral audio
  or video prayer rooms. It contains no media. `livekit-token` checks the caller is active, in the meeting's
  parish, and an actual Circle member before returning a 15-minute, room-scoped
  LiveKit JWT. `LIVEKIT_API_SECRET` stays only in Supabase Edge secrets.
- Circle photos live under `circle-images/<circle-id>/…`; only Circle owner or
  admin roles can write that folder. A live-meeting notification uses the
  existing `system` notification type and respects the member's mute setting.

### 0046 Host-controlled Circle recordings

- `circle_recordings` stores only recording state and audit metadata; media is
  written by LiveKit Egress into the private `mathetes-recordings` Cloudflare R2
  bucket. R2 credentials, the LiveKit API secret, and signed URL generation are
  confined to `manage-circle-recording` Edge Function secrets.
- Only active Circle `owner` / `admin` members may start or stop a recording.
  Every caller (including playback) is re-checked for active same-parish Circle
  membership. The function issues a fresh 15-minute signed R2 GET URL only for
  `ready` files; direct bucket access is never provided to the app.
- Recording is **opt-in and visible**: there is no automatic/covert capture.
  On start and stop, unmuted Circle members receive a `system` notification;
  the live app shows a red recording banner. A partial unique index prevents two
  admins from creating simultaneous billable egress jobs for one meeting.

### 0047 Member profile presence

- `user_profiles.bio` (280 characters) and `user_profiles.thought` (180
  characters) give an active parish member a small, human profile. They inherit
  the existing `user_profiles` RLS rule—there is no public profile, follower
  graph, or activity feed. `thought_updated_at` records when a current thought
  was last changed.

### 0048–0049 Daily encouragement and library

- Daily Word and devotionals have live **Amen** and **Share** totals scoped to
  the parish. Per-member contribution rows are never readable by clients;
  clients receive only aggregate counts and their own Amen state. This is a
  quiet encouragement mechanism, not a feed, ranking, or social score.
- `word_bookmarks`, `word_notes`, `devotional_bookmarks`, and
  `devotional_notes` are private to their creator. A saved item or reflection
  can only target daily content already visible in that member's parish.

### 0050 Formation badges

- `formation_badges` defines a small set of universal milestones and
  `member_badges` is readable only by its owner. The trusted activity logger
  awards badges idempotently after a real practice (Word, devotional,
  reflection, prayer, plan day, share, or shared practice). There is no admin
  report of who has or has not earned one.
