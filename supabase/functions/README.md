# Edge Functions

Deno edge functions for Mathetes. Two are triggered by **Database Webhooks**,
two by a **schedule**.

| Function | Trigger | What it does |
|----------|---------|--------------|
| `send-push` | Webhook: `INSERT` on `public.notifications` | Sends Expo push to the recipient's `push_tokens`, honours the per-type push preference, prunes dead tokens |
| `moderate-message` | Webhook: `INSERT` on `public.messages` | OpenAI moderation; soft-deletes flagged messages and writes `moderation_log` |
| `daily-content-publish` | Schedule: `1 0 * * *` (00:01 UTC) | Publishes scheduled WOTD/devotionals for the day; notifies parish members of today's Word |
| `archive-term` | Schedule: daily | Soft-archives house/discipler/DM messages `ARCHIVE_AFTER_DAYS` after `TERM_END_DATE` (dry-run unless `ARCHIVE_CONFIRM=true`) |

## Environment / secrets

Set via `supabase secrets set` (or the dashboard):

```
SUPABASE_URL                # auto-injected in the platform
SUPABASE_SERVICE_ROLE_KEY   # auto-injected in the platform
OPENAI_API_KEY              # moderate-message
TERM_END_DATE=2026-07-31    # archive-term (ISO date)
ARCHIVE_AFTER_DAYS=60       # archive-term (optional, default 60)
ARCHIVE_CONFIRM=false       # archive-term safety switch
```

## Deploy

```bash
supabase functions deploy send-push moderate-message daily-content-publish archive-term
```

## Wiring the triggers (one-time, in the Supabase dashboard or SQL)

`config.toml` sets `verify_jwt = false` for all four (they are not called with an
end-user JWT). Then:

- **Webhooks** (Database → Webhooks): create an `INSERT` webhook on
  `public.notifications` → `send-push`, and on `public.messages` →
  `moderate-message`.
- **Schedules** (Edge Functions → Cron, or `pg_cron` + `pg_net`):
  `daily-content-publish` at `1 0 * * *`, `archive-term` daily.

These hooks live outside the migration chain on purpose: they depend on
`pg_net` / `pg_cron` and platform config, so they are configured per environment
rather than baked into a migration (which keeps the schema portable and the
stub-based smoke test green).

## Giving (V2.1, Paystack)

| Function | Trigger | What it does |
|----------|---------|--------------|
| `paystack-initialize` | User call (JWT) | Validates fund/amount, creates a PENDING donation (one-time) or recurring mandate + Paystack plan, calls Paystack `/transaction/initialize`, returns `authorization_url` |
| `paystack-webhook` | Paystack webhook (no JWT) | Verifies `x-paystack-signature` (HMAC-SHA512), logs every event, records `charge.success` / `subscription.create` / `invoice.payment_failed` / `subscription.disable` idempotently |

Secrets: `PAYSTACK_SECRET_KEY` (both), plus the standard `SUPABASE_URL` /
`SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`. In the **Paystack dashboard**,
set the webhook URL to the deployed `paystack-webhook` function URL. The client
holds only the Paystack **public** key + the returned checkout URL.

| `paystack-manage-recurring` | User call (JWT) | Cancel / pause / resume the caller's own recurring mandate (ownership-checked; Paystack subscription enable/disable). Body: `{ recurring_id, action: 'cancel'|'pause'|'resume' }` |

`paystack-initialize` now also returns `access_code` (for the Paystack inline SDK)
alongside `authorization_url`. `donations` + `giving_recurring` are in the
`supabase_realtime` publication (0024) so clients can watch gift/mandate status.
