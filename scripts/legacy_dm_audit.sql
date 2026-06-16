-- legacy_dm_audit.sql  (run by an operator against PROD; not a migration)
--
-- Finding from launch prep: DMs created before 0021 (house-mate-only DMs) may
-- have house_id NULL and therefore NO house-leader oversight. This script:
--   (a) repairs DMs whose two participants share one house  -> set chats.house_id;
--   (b) archives the rest (different/no shared house) and notifies both members.
--
-- NOTE: chats has no archived_at column in the migrations yet; this adds it
-- idempotently. Formalize it in a follow-up migration so repo and prod stay in
-- sync (e.g. 0023_chats_archived_at.sql).
--
-- Review the audit output first, then run inside a transaction.

-- 0. Audit: what's affected?
select id, created_at, kind, house_id, parish_id, created_by
from public.chats
where kind = 'dm' and house_id is null
order by created_at;

begin;

alter table public.chats add column if not exists archived_at timestamptz;

-- Per-DM participant house summary (exactly-two-member DMs).
create temp table _dm_fix on commit drop as
select c.id as chat_id,
       count(*)               as n_members,
       count(p.house_id)      as n_with_house,
       min(p.house_id::text)  as h_min,
       max(p.house_id::text)  as h_max
from public.chats c
join public.chat_members m on m.chat_id = c.id
join public.user_profiles p on p.id = m.user_id
where c.kind = 'dm' and c.house_id is null and c.archived_at is null
group by c.id;

-- (a) Repair: both participants in the same single house -> adopt it.
update public.chats c
  set house_id = f.h_min::uuid
from _dm_fix f
where c.id = f.chat_id
  and f.n_members = 2 and f.n_with_house = 2 and f.h_min = f.h_max;

-- (b) Archive the remainder (cross-house or missing-house -> un-overseeable).
update public.chats c
  set archived_at = now()
from _dm_fix f
where c.id = f.chat_id
  and c.house_id is null
  and not (f.n_members = 2 and f.n_with_house = 2 and f.h_min = f.h_max);

-- Notify both members of each archived DM (idempotent).
insert into public.notifications (user_id, type, title, preview, target_id, target_url)
select m.user_id, 'system', 'A conversation was ended',
       'This direct message was closed in line with our pastoral guardrails: messages need a shared house for leader oversight.',
       c.id, 'mathetes://chat/' || c.id
from public.chats c
join public.chat_members m on m.chat_id = c.id
where c.kind = 'dm' and c.archived_at is not null
  and not exists (
    select 1 from public.notifications n
    where n.target_id = c.id and n.user_id = m.user_id and n.type = 'system'
      and n.title = 'A conversation was ended'
  );

-- Report counts before committing.
select
  (select count(*) from public.chats where kind='dm' and house_id is not null and archived_at is null) as repaired_or_ok,
  (select count(*) from public.chats where kind='dm' and archived_at is not null) as archived;

-- Review the counts above, then:  COMMIT;   (or ROLLBACK; to abort)
commit;
