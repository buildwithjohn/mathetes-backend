-- 0023_giving.sql
-- V2.1 — Giving (tithes / offerings / designated funds) via Paystack.
--
-- MONEY GUARDRAILS (non-negotiable; encoded in RLS + the edge functions):
--   * We store NO card or bank details. Paystack tokenizes payment; we keep only
--     a reference, amount, fund, status, channel, and timestamps.
--   * Giving is PRIVATE: a giver sees only their own gifts + recurring mandates;
--     pastor/finance admins see their parish's records for reconciliation. There
--     are NO public donor lists, amounts, or leaderboards.
--   * All writes are server-mediated. Members have NO INSERT/UPDATE on donations
--     or recurring mandates — those rows are created by the paystack-initialize
--     edge function and confirmed by the paystack-webhook (both service-role).
--     The Paystack SECRET key never leaves the edge runtime.
--   * Amounts are in KOBO (NGN minor units), the unit Paystack expects.
--   * The webhook is idempotent: every event is logged in paystack_events and a
--     charge is only counted once.

-- ---------------------------------------------------------------------------
-- Funds (admin-managed designations)
-- ---------------------------------------------------------------------------

create table if not exists public.giving_funds (
  id          uuid primary key default gen_random_uuid(),
  parish_id   uuid not null references public.parishes(id) on delete cascade,
  slug        text not null,
  name        text not null,
  description text,
  active      boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (parish_id, slug)
);

-- ---------------------------------------------------------------------------
-- Recurring giving mandates (Paystack plan + subscription)
-- ---------------------------------------------------------------------------

create table if not exists public.giving_recurring (
  id                         uuid primary key default gen_random_uuid(),
  parish_id                  uuid not null references public.parishes(id) on delete cascade,
  user_id                    uuid not null references public.user_profiles(id) on delete cascade,
  fund_id                    uuid references public.giving_funds(id) on delete set null,
  amount_kobo                integer not null check (amount_kobo > 0),
  currency                   text not null default 'NGN',
  interval                   text not null check (interval in ('weekly','monthly','quarterly','annually')),
  status                     text not null default 'pending'
                               check (status in ('pending','active','paused','attention','cancelled')),
  anonymous                  boolean not null default false,
  note                       text,
  paystack_customer_code     text,
  paystack_plan_code         text,
  paystack_subscription_code text,
  paystack_email_token       text,           -- needed to disable a subscription
  next_payment_at            timestamptz,
  started_at                 timestamptz,
  cancelled_at               timestamptz,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Donations (one-time gifts and recurring cycle charges)
-- ---------------------------------------------------------------------------

create table if not exists public.donations (
  id                 uuid primary key default gen_random_uuid(),
  parish_id          uuid not null references public.parishes(id) on delete cascade,
  user_id            uuid not null references public.user_profiles(id) on delete cascade,
  fund_id            uuid references public.giving_funds(id) on delete set null,
  recurring_id       uuid references public.giving_recurring(id) on delete set null,
  amount_kobo        integer not null check (amount_kobo > 0),
  fees_kobo          integer,
  currency           text not null default 'NGN',
  kind               text not null default 'one_time' check (kind in ('one_time','recurring')),
  status             text not null default 'pending'
                       check (status in ('pending','success','failed','abandoned','reversed')),
  reference          text not null unique default ('gv_' || replace(gen_random_uuid()::text, '-', '')),
  paystack_reference text,
  channel            text,
  anonymous          boolean not null default false,
  note               text,
  paid_at            timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Webhook event log (audit + idempotency)
-- ---------------------------------------------------------------------------

create table if not exists public.paystack_events (
  id              uuid primary key default gen_random_uuid(),
  event_type      text not null,
  reference       text,
  paystack_id     text,                       -- event/data id from Paystack
  signature_valid boolean not null default false,
  processed       boolean not null default false,
  error           text,
  payload         jsonb not null,
  created_at      timestamptz not null default now(),
  processed_at    timestamptz
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists idx_giving_funds_parish on public.giving_funds (parish_id, active, sort_order);
create index if not exists idx_giving_recurring_user on public.giving_recurring (user_id, status);
create index if not exists idx_giving_recurring_parish on public.giving_recurring (parish_id, status);
create index if not exists idx_donations_user on public.donations (user_id, created_at desc);
create index if not exists idx_donations_parish_status on public.donations (parish_id, status, paid_at desc);
create index if not exists idx_donations_recurring on public.donations (recurring_id);
create index if not exists idx_paystack_events_ref on public.paystack_events (reference);
create unique index if not exists uq_paystack_events_id on public.paystack_events (paystack_id) where paystack_id is not null;

-- updated_at triggers (set_updated_at from 0002)
drop trigger if exists trg_giving_funds_updated_at on public.giving_funds;
create trigger trg_giving_funds_updated_at before update on public.giving_funds
  for each row execute function public.set_updated_at();
drop trigger if exists trg_giving_recurring_updated_at on public.giving_recurring;
create trigger trg_giving_recurring_updated_at before update on public.giving_recurring
  for each row execute function public.set_updated_at();
drop trigger if exists trg_donations_updated_at on public.donations;
create trigger trg_donations_updated_at before update on public.donations
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.giving_funds     enable row level security;
alter table public.giving_recurring enable row level security;
alter table public.donations        enable row level security;
alter table public.paystack_events  enable row level security;

-- Funds: members read active funds in their parish (to choose where to give);
-- admins manage.
create policy "giving_funds_select" on public.giving_funds for select
  to authenticated
  using (parish_id = public.current_parish_id() and (active or public.is_parish_admin()));
create policy "giving_funds_admin_write" on public.giving_funds for all
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Donations: giver reads own; parish admins (finance) read their parish's.
-- No member write path — created/updated only by the service role (edge fns).
create policy "donations_select_own" on public.donations for select
  to authenticated
  using (user_id = public.current_profile_id());
create policy "donations_select_admin" on public.donations for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Recurring mandates: same visibility model; writes via service role only.
create policy "giving_recurring_select_own" on public.giving_recurring for select
  to authenticated
  using (user_id = public.current_profile_id());
create policy "giving_recurring_select_admin" on public.giving_recurring for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- Webhook log: parish admins may audit; members have no access; service role writes.
create policy "paystack_events_admin_select" on public.paystack_events for select
  to authenticated
  using (public.is_parish_admin());

-- ---------------------------------------------------------------------------
-- Seed default funds for the pilot parish (admin can rename/retire later).
-- ---------------------------------------------------------------------------

insert into public.giving_funds (parish_id, slug, name, description, sort_order) values
  ('00000000-0000-0000-0000-000000000001', 'tithe',    'Tithe',         'Your regular tithe to the parish.',            1),
  ('00000000-0000-0000-0000-000000000001', 'offering', 'Offering',      'General offering.',                            2),
  ('00000000-0000-0000-0000-000000000001', 'building', 'Building Fund', 'Toward the parish building project.',          3),
  ('00000000-0000-0000-0000-000000000001', 'missions', 'Missions',      'Supporting campus and field missions.',        4)
on conflict (parish_id, slug) do nothing;
