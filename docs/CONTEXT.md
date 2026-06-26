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

**Repo HEAD: migration `0032`.** Prod is applied piecemeal; confirm what's live:
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
| `create_dm` | `p_other uuid` | `uuid` (chat id) | **Role-aware (0033).** Same parish + active target for everyone. **Students** (and house leaders): same non-null house (B1) + cross-gender approval (B2). **Leaders** — owner / pastor / admin, and any caller toward their **own disciples** (`discipler_id` pointer) — may DM any active parish member, cross-house, cross-gender approval bypassed (pastoral care). Idempotent (reuses existing DM, never re-gated) |
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
`set_updated_at`, `notify_on_message`/`notify_on_answer`/`notify_on_announcement`,
`sync_house_chat_membership`, `sync_discipler_chat`,
`bible_verses_search_vector`, `bible_sync_verse_count`.

---

## 5. Edge functions (Deno)

**Not deployed yet** for giving (Paystack account pending). The webhook/cron
functions are written but must be deployed + wired per environment (they live
outside the migration chain by design — they depend on `pg_net`/`pg_cron`).

| Function | Trigger | Contract |
|----------|---------|----------|
| `send-push` | Webhook: INSERT on `notifications` | Sends Expo push to recipient `push_tokens`, honours per-type pref, prunes dead tokens |
| `moderate-message` | Webhook: INSERT on `messages` | OpenAI moderation; soft-deletes flagged messages, writes `moderation_log` |
| `daily-content-publish` | Cron `1 0 * * *` | Publishes scheduled WOTD/devotionals; notifies parish of today's Word |
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
| `content-media` | pastor/admin | devotional audio/video **and** Library files (PDF/audio/video/covers); 512 MB limit, MIME-restricted (0031) |

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
