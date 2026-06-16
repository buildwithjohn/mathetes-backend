# Mathetes — Full Engagement Handoff (as of 2026-06-16)

Context for the PM and anyone picking this up. The branch-cleanup task was
backend-only, but a lot more was built and shipped across this engagement that
the PM did not have context on. This document captures **all of it**, the
decisions taken, and what remains. Authorized by the project owner (see end).

---

## 1. Repositories, branches, and current state

| Repo | Working branch (default) | Latest commit | State |
|------|--------------------------|---------------|-------|
| `buildwithjohn/mathetes-backend` | `claude/ecstatic-edison-nvdJF` | `ac17a8e` | Migrations 0001–0021, full KJV, edge fns, tests/CI, canonical types. All merged + pushed. |
| `buildwithjohn/mathetes-mobile` | `claude/sharp-davinci-rHLiO` | `8f1ad11` | Expo SDK 54 app, wired to cloud, typechecks + bundles. |
| `buildwithjohn/mathetes-admin` | `claude/loving-sagan-23mIP` | `ba0af49` | Next.js 15.5 admin, wired to cloud; builds. (Advanced past my `3bcaae3`.) |

**Cloud Supabase project:** ref `jowokfnlfqqjzwhvnmxj`, region `eu-west-1`.
Schema is deployed there (applied out-of-band via `psql`, not the CLI).

> Note: the "default" branch is the `claude/ecstatic-edison-nvdJF` line, not
> `main`. Production tracks the merged backend work.

---

## 2. What was built (chronological, across the whole engagement)

### Backend (mathetes-backend) — built from empty repo
- **Migrations 0001–0014** (my work): identity/parishes/houses, content
  (devotionals/WOTD), Bible (FTS + `search_bible`/`get_chapter`/`parse_reference`),
  personal library, engagement (streaks w/ grace day), **chat with pastoral
  oversight RLS**, prayer wall, ask-pastor (anonymized `public_qa`), safety
  (blocks/reports/moderation, block-hides-messages), notifications, verse images,
  bible search tuning, storage buckets, announcements table.
- **Full KJV** (31,102 verses, 1,189 chapters) in `supabase/seed/kjv.sql`.
- **4 edge functions** (`send-push`, `moderate-message`, `daily-content-publish`,
  `archive-term`) — written, not yet deployed/wired.
- **Test harnesses + CI**: `scripts/test-migrations.sh`, `scripts/test-rls.sh`
  (now 36 assertions), `scripts/test-kjv.sh`; GitHub Actions runs all three.
- **Deployed to cloud** via `scripts/deploy-cloud.sh` + `psql` (sandbox can't
  reach the DB directly — see §5). Storage migration (0013) applied separately.

### Branch cleanup + guardrails (the PM's task)
- Merged **`chat-media-storage`** (0015 chat-media bucket/public avatars, 0016
  campuses, 0017 parish_chat, 0018 per-campus houses + member dob/phone) into
  default — clean fast-forward, no conflicts.
- Merged **`content-media-video`**: rebased, renamed `0017_content_media` →
  **`0019_content_media`** (devotionals.video_url + content-media bucket).
- `announcements-table` and `kjv-full-import` branches are **superseded** by work
  already on default; intentionally not merged.
- **Finding B2 (cross-gender DM)** → `0020_cross_gender_dm.sql`.
- **Finding B1 (cross-house DM)** → `0021_cross_house_dm.sql` (authoritative
  `create_dm`). See §4 for the guardrail decision.
- **Finding B4 (realtime)** documented in `docs/data-model.md` (verify + dashboard
  remedy).
- **Canonical types** at `types/database.types.ts` (single source of truth).
- Updated the `7 → 14 houses` RLS assertion after the per-campus split.

### Mobile (mathetes-mobile)
- Reconciled the data layer with the deployed schema (added
  `user_profiles.discipler_id`); `tsc` clean.
- Pointed `.env` at the cloud project.
- **Upgraded Expo SDK 51 → 54** (React 19 / RN 0.81, Reanimated 4 +
  `react-native-worklets`, NativeWind 4.2, lucide bump, `.npmrc`
  legacy-peer-deps) so Expo Go (which only supports the latest SDK) runs the
  app. Verified with `tsc` **and** a successful `expo export` bundle.

### Admin (mathetes-admin)
- Reconciled with the deployed schema — this is **why the backend gained the
  `announcements` table (0014)**: the admin authors announcements into a table.
- Pointed env at the cloud project; added `.npmrc`.
- **Patched Next 15.0.3 → 15.5.19** (CVE-2025-66478). `tsc` + `next build` pass.

### Auth / test logins
Two demo accounts created (via SQL in the Supabase SQL editor, email-confirmed):

| Role | App | Email | Password |
|------|-----|-------|----------|
| Pastor (admin) | admin web | `pastor@cccfsp.app` | `Mathetes-Pastor-2026` |
| Student | mobile | `student@cccfsp.app` | `Mathetes-Student-2026` |

Resolved two gotchas along the way: the app's older `supabase-js` needs the
**legacy `anon` (JWT) key**, not the new `sb_publishable_…` key; and the role/
house SQL only works after the auth users exist.

---

## 3. Pastoral guardrails — current status (non-negotiable)

- **DMs**: now house-mate-to-house-mate only (B1), so every DM has a house leader
  for oversight. House leader sees DM existence/oversight; pastor does **not** see
  DMs. Cross-gender DMs require recipient approval unless they opted out (B2).
- **Discipler chats**: pastor oversight (read-only).
- **Ask Pastor**: public answers anonymized via `public_qa`; `asker_id` never
  leaks.
- **Blocks**: a block hides the blocked user's messages (restrictive RLS).
- **`parish_group`** (new general room): readable+writable by all parish members
  including the pastor → accountable by design, not a private channel.
- Oversight everywhere is **read-only**. 36 RLS assertions encode these and pass.

---

## 4. Key decisions taken (please ratify)

1. **B1 strengthened beyond the literal spec.** The PM's Option A only blocked
   cross-house DMs when both houses are set, which still let *house-less* users
   open un-overseen DMs. I blocked those too: a DM requires the **same, non-null
   house**. This fully closes the "messaging without accountability" hole and
   matches the `dm_who='house'` default. Cross-campus DMs are blocked as a side
   effect (they're cross-house under 0018).
2. **B1 + B2 as append-only migrations** (0020, 0021); `0006_chat.sql` untouched.
3. **`announcements` modeled as a table** (0014) to match the admin, in addition
   to the existing announcements chat channel.
4. **Canonical types generated by schema introspection** (the Supabase CLI needs
   Docker, unavailable in the agent sandbox). It is accurate and `tsc`-validated;
   regenerate authoritatively with the CLI when convenient.
5. **Mobile/admin keep their own `database.types.ts`** for now (they carry
   convenience aliases the canonical file doesn't). Adopting the canonical file
   is a follow-up (add the alias re-exports first).

---

## 5. Environment constraints that shaped how this was done

The agent ran in a sandbox that **only allows outbound HTTPS (443)**. Therefore
the agent could **not**: reach the cloud Postgres (5432/6543 firewalled), run
`supabase gen types` (needs Docker), or push via the default origin proxy
(returned 403). Workarounds used: `psql`/migrations executed by the human on
their Mac; types via introspection; git pushes via a personal access token.

**Consequences requiring a human (you):** the two "verify against cloud" steps
(`schema_migrations` list, realtime publication check) could not be run by the
agent and are listed below.

---

## 6. Outstanding actions (human-run)

1. **Production migration reconciliation.** Run
   `select version, name from supabase_migrations.schema_migrations order by version;`
   then apply any missing of `0019_content_media`, `0020_cross_gender_dm`,
   `0021_cross_house_dm` (idempotent, append-only), and confirm 0015–0018 are
   present.
2. **Realtime (B4).** Verify `supabase_realtime` includes `messages`,
   `message_reactions`, `chat_members`, `notifications`; enable any missing in
   Dashboard → Database → Replication (see `docs/data-model.md`).
3. **Legacy DM audit.** `select count(*) from public.chats where kind='dm' and house_id is null;`
   — any pre-B1 rows are un-overseen; decide archive vs. assign oversight.
4. **Authoritative types regen** via `supabase gen types typescript --project-id
   jowokfnlfqqjzwhvnmxj > types/database.types.ts`, then reconcile mobile/admin.
5. **Edge functions**: `supabase functions deploy` + wire Database Webhooks
   (send-push, moderate-message) and cron (daily-content-publish, archive-term).
6. **Auth for pilot**: turn off "Confirm email" (or configure SMTP) so mobile
   signup → house selection completes.
7. **Rotate secrets** that were shared in chat during setup: the database
   password and the GitHub PAT used for pushes.

---

## 7. Authorization

The project owner — **John (akinolajohnayomide@gmail.com, GitHub `buildwithjohn`)**
— authorizes all of the work, merges, deployments, and decisions described
above, including the cross-repo (mobile + admin) changes that fell outside the
original backend-only task scope, and the B1 guardrail strengthening in §4.
