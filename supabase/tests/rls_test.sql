-- rls_test.sql
-- Regression assertions for the Mathetes RLS guardrails. Run via
-- scripts/test-rls.sh against a fresh DB (auth stubs + migrations + seed).
--
-- The whole suite runs in one transaction and ROLLBACKs at the end, so it
-- leaves no residue. Each check switches to the `authenticated` role with a
-- JWT `sub` GUC (so auth.uid() resolves) and asserts what that user can see.
-- Assertions are `select public.t_assert(<cond>, '<label>')`; a false/null
-- condition raises and aborts the run (psql ON_ERROR_STOP).

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off

begin;

-- Let RLS (not missing grants) govern access for the authenticated role.
do $grants$ declare r record; begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', r.tablename);
  end loop;
  grant usage on schema public to authenticated;
  grant execute on all functions in schema public to authenticated;
end $grants$;

create or replace function public.t_assert(cond boolean, label text)
returns void language plpgsql as $fn$
begin
  if cond is null or cond = false then
    raise exception 'ASSERTION FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end $fn$;
grant execute on function public.t_assert(boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (run as the table owner; bypasses RLS).
-- ---------------------------------------------------------------------------

-- A second parish, to test parish isolation.
insert into public.parishes (id, slug, name, abbr)
values ('00000000-0000-0000-0000-0000000000ff', 'other-parish', 'Other Parish', 'OTH');

insert into auth.users (id, email, raw_user_meta_data) values
  ('0a000000-0000-0000-0000-000000000001', 'ada@x',    '{"name":"Ada"}'),
  ('0b000000-0000-0000-0000-000000000002', 'bode@x',   '{"name":"Bode"}'),
  ('0c000000-0000-0000-0000-000000000003', 'tope@x',   '{"name":"Tope"}'),
  ('0d000000-0000-0000-0000-000000000004', 'pastor@x', '{"name":"Pastor"}'),
  ('0e000000-0000-0000-0000-000000000005', 'disc@x',   '{"name":"Discipler"}'),
  ('0f000000-0000-0000-0000-000000000006', 'beth@x',   '{"name":"Bethel One"}'),
  ('10000000-0000-0000-0000-000000000007', 'other@x',  '{"name":"Other One"}');

-- Tope leads Berea (set before assigning his house so membership = leader).
update public.houses set leader_id = (select id from public.user_profiles where auth_id = '0c000000-0000-0000-0000-000000000003')
  where slug = 'berea';

update public.user_profiles set house_id = (select id from public.houses where slug = 'berea')
  where auth_id in ('0a000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000002',
                    '0c000000-0000-0000-0000-000000000003','0e000000-0000-0000-0000-000000000005');
update public.user_profiles set house_id = (select id from public.houses where slug = 'bethel')
  where auth_id = '0f000000-0000-0000-0000-000000000006';
update public.user_profiles set role = 'pastor' where auth_id = '0d000000-0000-0000-0000-000000000004';
-- Other One belongs to the second parish.
update public.user_profiles set parish_id = '00000000-0000-0000-0000-0000000000ff', house_id = null
  where auth_id = '10000000-0000-0000-0000-000000000007';

-- DM-guardrail fixtures (Findings B1/B2): two male + two female house-mates in
-- ZION (kept out of Berea so they don't perturb the Berea notification fan-out
-- assertion). Ms Two (f2) opts out of cross-gender approval; others keep default.
insert into auth.users (id, email, raw_user_meta_data) values
  ('0d111111-0000-0000-0000-000000000001', 'm1@x', '{"name":"Mr One"}'),
  ('0d111111-0000-0000-0000-000000000002', 'm2@x', '{"name":"Mr Two"}'),
  ('0d111111-0000-0000-0000-000000000003', 'f1@x', '{"name":"Ms One"}'),
  ('0d111111-0000-0000-0000-000000000004', 'f2@x', '{"name":"Ms Two"}');
update public.user_profiles
  set house_id = (select id from public.houses where slug = 'zion'),
      gender = case when auth_id in ('0d111111-0000-0000-0000-000000000001','0d111111-0000-0000-0000-000000000002')
                    then 'male' else 'female' end
  where auth_id::text like '0d111111-%';
update public.user_privacy set cross_gender_dm_approval = false
  where user_id = (select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000004');

-- Owner (admin + is_owner) and a plain (non-owner) admin for management tests.
insert into auth.users (id, email, raw_user_meta_data) values
  ('0d000000-0000-0000-0000-0000000000aa', 'owner@x',  '{"name":"Owner"}'),
  ('0d000000-0000-0000-0000-0000000000ab', 'padmin@x', '{"name":"Plain Admin"}');
update public.user_profiles set role = 'admin', is_owner = true  where auth_id = '0d000000-0000-0000-0000-0000000000aa';
update public.user_profiles set role = 'admin', is_owner = false where auth_id = '0d000000-0000-0000-0000-0000000000ab';

-- 0025 membership gating: the new handle_new_user defaults unmatched email
-- domains (all the '@x' test users) to status='pending' with a null parish.
-- Activate every fixture member and put them in the pilot parish so the prior
-- sections behave as before (the other-parish user keeps its parish).
update public.user_profiles set status = 'active';
update public.user_profiles set parish_id = '00000000-0000-0000-0000-000000000001' where parish_id is null;

-- One still-PENDING member (no matching domain → no campus/parish) for gating tests.
insert into auth.users (id, email, raw_user_meta_data) values
  ('0f111111-0000-0000-0000-000000000099', 'pending@x', '{"name":"Pending Pat"}');
select id as pend from public.user_profiles where auth_id = '0f111111-0000-0000-0000-000000000099' \gset

-- One SUSPENDED in-parish member (house null -> no chat fan-out) for the 0033
-- leader-directory test: hidden from students, visible to parish admins.
insert into auth.users (id, email, raw_user_meta_data) values
  ('0f111111-0000-0000-0000-0000000000a8', 'susp@x', '{"name":"Suspended Sam"}');
update public.user_profiles
  set status = 'suspended', parish_id = '00000000-0000-0000-0000-000000000001', house_id = null
  where auth_id = '0f111111-0000-0000-0000-0000000000a8';
select id as susp from public.user_profiles where auth_id = '0f111111-0000-0000-0000-0000000000a8' \gset

-- Profile ids for convenience.
select id as ada  from public.user_profiles where auth_id = '0a000000-0000-0000-0000-000000000001' \gset
select id as bode from public.user_profiles where auth_id = '0b000000-0000-0000-0000-000000000002' \gset
select id as disc from public.user_profiles where auth_id = '0e000000-0000-0000-0000-000000000005' \gset

-- Discipler relationship -> creates the discipler chat.
update public.user_profiles set discipler_id = :'disc' where id = :'ada';

-- Ada opens a DM with Bode (must act as Ada for create_dm).
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.create_dm(:'bode') as dm \gset
insert into public.messages (chat_id, author_id, body) values (:'dm', :'ada', 'Praying for you today.');
reset role;
-- Bode replies (authored as Bode) so the DM has 2 messages: proves the report
-- path exposes ONLY the reported one, not the whole thread.
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into public.messages (chat_id, author_id, body) values (:'dm', :'bode', 'Thank you, means a lot.');
reset role;

-- The DM message Ada will later report (drives the 0029 report-path checks).
select id as dmsg from public.messages where chat_id = :'dm' and body = 'Praying for you today.' limit 1 \gset

-- Capture remaining chat ids as owner.
select c.id as dchat from public.chats c
  join public.chat_members m on m.chat_id = c.id and m.user_id = :'disc'
  where c.kind = 'discipler' limit 1 \gset
select c.id as hchat from public.chats c
  join public.houses h on h.id = c.house_id and h.slug = 'berea'
  where c.kind = 'house_group' limit 1 \gset

-- Bode posts in the Berea house chat (drives block + notification checks).
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into public.messages (chat_id, author_id, body) values (:'hchat', :'bode', 'Good morning, house!');
reset role;

-- ===========================================================================
-- 1. CHAT OVERSIGHT (the core pastoral guardrail)
-- ===========================================================================

-- DM (0029): private to participants only. Leaders no longer get passive
-- oversight; pastors & outsiders cannot read or even see DM existence.
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select public.can_read_chat(:'dm')), 'DM: participant (Ada) can read');
reset role;

-- House leader Tope: 0029 removed passive DM oversight entirely.
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.t_assert((select not public.can_read_chat(:'dm')), 'DM: house leader (Tope) CANNOT browse a private DM (0029)');
select public.t_assert((select count(*) = 0 from public.messages where chat_id = :'dm'), 'DM: house leader sees no DM messages');
reset role;

select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.t_assert((select not public.can_read_chat(:'dm')), 'DM: pastor CANNOT read');
select public.t_assert((select count(*) = 0 from public.chats where id = :'dm'), 'DM: pastor cannot see DM existence');
select public.t_assert((select count(*) = 0 from public.messages where chat_id = :'dm'), 'DM: pastor sees no DM messages');
reset role;

select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select public.t_assert((select not public.can_read_chat(:'dm')), 'DM: other-house member CANNOT read');
select public.t_assert((select count(*) = 0 from public.messages where chat_id = :'dm'), 'DM: outsider sees no DM messages');
reset role;

-- Report path (0029): a participant reports a specific DM message; ONLY that
-- message becomes visible to parish admin/pastor. Browsing stays blocked.
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.reports (parish_id, reporter_id, target_type, target_id, reason)
  values ('00000000-0000-0000-0000-000000000001', :'ada', 'message', :'dmsg', 'harassment');
reset role;

select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.t_assert((select not public.can_read_chat(:'dm')), 'DM report: pastor still cannot browse the DM');
select public.t_assert((select count(*) = 1 from public.messages where chat_id = :'dm'), 'DM report: pastor sees ONLY the reported message');
select public.t_assert((select body = 'Praying for you today.' from public.messages where chat_id = :'dm'), 'DM report: the one visible message is the reported one');
reset role;

-- A non-admin outsider gains nothing from the report.
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.messages where chat_id = :'dm'), 'DM report: report does not expose the message to other members');
reset role;

-- Discipler chat: pastor oversees; house leader does NOT; disciple reads.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.t_assert((select public.can_read_chat(:'dchat')), 'Discipler: pastor has oversight read');
reset role;
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.t_assert((select not public.can_read_chat(:'dchat')), 'Discipler: house leader CANNOT read');
reset role;
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select public.can_read_chat(:'dchat')), 'Discipler: disciple (participant) can read');
reset role;

-- ===========================================================================
-- 2. PARISH ISOLATION
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
-- Since 0018 (per-campus houses) the pilot parish has 14 houses (7 Oye + 7 Ikole).
-- House RLS stays parish-wide; the app filters by campus client-side.
select public.t_assert((select count(*) = 14 from public.houses), 'Isolation: CCCFSP member sees 14 houses (7 per campus)');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.houses), 'Isolation: other-parish member sees 0 CCCFSP houses');
select public.t_assert((select count(*) = 0 from public.word_of_day), 'Isolation: other-parish member sees 0 CCCFSP WOTD');
reset role;

-- ===========================================================================
-- 3. ASK PASTOR: public answers are anonymized; raw row never leaks
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.ask_questions (parish_id, asker_id, body)
  values ('00000000-0000-0000-0000-000000000001', :'ada', 'How do I forgive?') returning id as q \gset
reset role;
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.answer_question(:'q', 'Forgiveness begins in prayer.', true);
-- Re-answer guard (0028): a stale re-submit cannot clobber the given answer.
do $ra$
declare v public.ask_questions;
begin
  v := public.answer_question((select id::text from public.ask_questions where body = 'How do I forgive?' limit 1), 'stale overwrite', false);
  perform public.t_assert(false, 'AskPastor re-answer expected a block');
exception when others then
  perform public.t_assert(sqlerrm like '%already answered%', 'AskPastor: re-answer guard blocks stale overwrite');
end $ra$;
reset role;
-- Another member (Bode) must NOT see the raw row, but SEES the anonymized feed.
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.ask_questions where id = :'q'), 'AskPastor: raw row hidden from other members');
select public.t_assert((select count(*) = 1 from public.public_qa where id = :'q'), 'AskPastor: anonymized public_qa visible to members');
reset role;

-- ===========================================================================
-- 4. PRAYER WALL house scoping
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.prayer_requests (parish_id, house_id, author_id, body)
  values ('00000000-0000-0000-0000-000000000001', (select id from public.houses where slug = 'berea'), :'ada', 'Exams')
  returning id as preq \gset
reset role;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.prayer_requests where id = :'preq'), 'Prayer: other-house member cannot see Berea request');
reset role;
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.prayer_requests where id = :'preq'), 'Prayer: Berea house-mate can see it');
reset role;

-- ===========================================================================
-- 5. BLOCK hides messages (RESTRICTIVE policy)
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.messages where chat_id = :'hchat' and author_id = :'bode'), 'Block: Ada sees Bode message before block');
insert into public.blocks (blocker_id, blocked_id) values (:'ada', :'bode');
select public.t_assert((select count(*) = 0 from public.messages where chat_id = :'hchat' and author_id = :'bode'), 'Block: Ada no longer sees Bode messages after block');
reset role;
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.messages where chat_id = :'hchat' and author_id = :'bode'), 'Block: one-directional (Bode still sees own message)');
reset role;

-- ===========================================================================
-- 6. NOTIFICATIONS fan-out (author excluded; Berea members Ada+Tope+Disc = 3)
-- ===========================================================================
select public.t_assert((select count(*) = 3 from public.notifications where type = 'message' and target_id = :'hchat'), 'Notify: house message notified 3 members (author excluded)');
select public.t_assert((select count(*) = 0 from public.notifications where type = 'message' and user_id = :'bode' and target_id = :'hchat'), 'Notify: author Bode not notified of his own house message');
select public.t_assert((select count(*) = 1 from public.notifications where type = 'ask_answered' and user_id = :'ada'), 'Notify: asker Ada notified of answer');

-- ===========================================================================
-- 7. BIBLE readable by all authenticated; search works
-- ===========================================================================
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);  -- other parish
set local role authenticated;
-- Bible is readable by every authenticated user, across parishes. Multiple
-- public-domain versions exist (KJV + WEB/BSB/ASV from 0030); each has 66 books.
select public.t_assert((select count(*) >= 4 from public.bible_versions), 'Bible: all versions readable across parishes');
select public.t_assert((select count(*) = 66 from public.bible_books b
  join public.bible_versions ver on ver.id = b.version_id where ver.code = 'KJV'), 'Bible: KJV has 66 books, readable cross-parish');
select public.t_assert((select reference = 'Proverbs 3:5' from public.search_bible('lean not unto', 'KJV') limit 1), 'Bible: search finds Proverbs 3:5');
reset role;

-- ===========================================================================
-- 8. STORAGE: you may write only your own avatar folder
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into storage.objects (bucket_id, name) values ('avatars', '0a000000-0000-0000-0000-000000000001/me.png');
select public.t_assert((select count(*) = 1 from storage.objects where bucket_id = 'avatars' and name like '0a000000%'), 'Storage: user can upload to own avatar folder');
do $blk$
begin
  begin
    insert into storage.objects (bucket_id, name) values ('avatars', '0b000000-0000-0000-0000-000000000002/evil.png');
    perform public.t_assert(false, 'Storage: writing another user''s folder must be blocked');
  exception when insufficient_privilege or check_violation then
    perform public.t_assert(true, 'Storage: writing another user''s folder is blocked');
  end;
end $blk$;
reset role;

-- ===========================================================================
-- 9. ANNOUNCEMENTS: members see published only; admins see drafts; publishing
--    notifies the parish.
-- ===========================================================================
select id as pastor from public.user_profiles where auth_id = '0d000000-0000-0000-0000-000000000004' \gset

select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
insert into public.announcements (parish_id, title, status)
  values ('00000000-0000-0000-0000-000000000001', 'Draft notice', 'draft') returning id as a_draft \gset
insert into public.announcements (parish_id, title, body_md, status, publish_date, posted_by)
  values ('00000000-0000-0000-0000-000000000001', 'Friday vigil', 'Join us at 6pm.', 'published', current_date, :'pastor')
  returning id as a_pub \gset
select public.t_assert((select count(*) = 1 from public.announcements where id = :'a_draft'), 'Announcements: admin sees own draft');
reset role;

select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);  -- Bode, member
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.announcements where id = :'a_pub'), 'Announcements: member sees published');
select public.t_assert((select count(*) = 0 from public.announcements where id = :'a_draft'), 'Announcements: member cannot see draft');
reset role;

select public.t_assert((select count(*) = 1 from public.notifications where type = 'announcement' and target_id = :'a_pub' and user_id = :'bode'), 'Announcements: publishing notifies a parish member');

-- ===========================================================================
-- 10. DM ACCOUNTABILITY (Finding B2 cross-gender, Finding B1 cross-house)
-- ===========================================================================
select set_config('request.jwt.claim.sub', '0d111111-0000-0000-0000-000000000001', true);  -- Mr One (male, Berea)
set local role authenticated;

-- B2: same-gender house-mate DM succeeds, no approval needed.
select public.t_assert(
  public.create_dm((select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000002')) is not null,
  'B2: same-gender house-mate DM succeeds');

-- B2: cross-gender DM to a recipient who opted OUT of approval succeeds.
select public.t_assert(
  public.create_dm((select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000004')) is not null,
  'B2: cross-gender DM to opted-out recipient succeeds');

-- B2: cross-gender DM to a recipient who requires approval is blocked.
do $b2$
declare v uuid;
begin
  v := public.create_dm((select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000003'));
  perform public.t_assert(false, 'B2 gate: expected a block, but the DM was created');
exception when others then
  perform public.t_assert(sqlerrm like '%cross-gender DM requires recipient approval%',
    'B2: cross-gender DM (approval required) is blocked');
end $b2$;

-- B1: cross-house DM is blocked (Mr One in Berea -> Bethel One in Bethel).
do $b1$
declare v uuid;
begin
  v := public.create_dm((select id from public.user_profiles where auth_id = '0f000000-0000-0000-0000-000000000006'));
  perform public.t_assert(false, 'B1 gate: expected a block, but the DM was created');
exception when others then
  perform public.t_assert(sqlerrm like '%cross-house DM blocked%',
    'B1: cross-house DM is blocked (no shared house leader)');
end $b1$;

-- 0033 LEADER REACH: owner/pastor/admin DM any active parish member (cross-house
-- + cross-gender bypassed); a member reaches only their own disciples (pointer).

-- Pastor (no house) DMs a member in Zion: a student would hit the no-shared-house
-- block; the pastor's leader reach succeeds.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);  -- Pastor
set local role authenticated;
select public.t_assert(
  public.create_dm((select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000001')) is not null,
  'LEAD1: pastor DMs a cross-house member (leader reach)');
reset role;

-- Owner DMs Ms One (female, requires cross-gender approval) in Zion: the student
-- gates would block on BOTH house and gender; the owner bypasses both.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-0000000000aa', true);  -- Owner
set local role authenticated;
select public.t_assert(
  public.create_dm((select id from public.user_profiles where auth_id = '0d111111-0000-0000-0000-000000000003')) is not null,
  'LEAD2: owner DMs cross-house + cross-gender (bypasses both gates)');
-- A NON-active target is still refused, even for the owner.
do $lead3$
declare v uuid;
begin
  v := public.create_dm((select id from public.user_profiles where auth_id = '0f111111-0000-0000-0000-0000000000a8'));
  perform public.t_assert(false, 'LEAD3 expected a block on a suspended target');
exception when others then
  perform public.t_assert(sqlerrm like '%not an active member%',
    'LEAD3: leader cannot DM a non-active member');
end $lead3$;
reset role;

-- Discipler reach is scoped to one's OWN disciples (pointer), not all members:
-- disc is Ada's discipler but NOT Bethel One's, so a cross-house DM there is
-- still blocked exactly like any student's.
select set_config('request.jwt.claim.sub', '0e000000-0000-0000-0000-000000000005', true);  -- Discipler (of Ada)
set local role authenticated;
do $lead4$
declare v uuid;
begin
  v := public.create_dm((select id from public.user_profiles where auth_id = '0f000000-0000-0000-0000-000000000006'));
  perform public.t_assert(false, 'LEAD4 expected a cross-house block for a non-disciple target');
exception when others then
  perform public.t_assert(sqlerrm like '%cross-house DM blocked%',
    'LEAD4: discipler reach does not extend to non-disciples');
end $lead4$;
reset role;
reset role;

-- ===========================================================================
-- 11. READING PLANS (V2.0) — privacy + discipler-share guardrails
-- ===========================================================================
-- Fixtures (as table owner): a published + an unpublished CCCFSP plan, a
-- published OTHER-parish plan, and two days on the published CCCFSP plan.
reset role;
insert into public.reading_plans (id, parish_id, slug, title, description, length_days, difficulty, published, published_at) values
  ('00000000-0000-0000-0000-0000000d0a01', '00000000-0000-0000-0000-000000000001', 'rp-pub',   'Pub Plan',   'd', 2, 'starter', true,  now()),
  ('00000000-0000-0000-0000-0000000d0a02', '00000000-0000-0000-0000-000000000001', 'rp-unpub', 'Unpub Plan', 'd', 2, 'starter', false, null),
  ('00000000-0000-0000-0000-0000000d0a03', '00000000-0000-0000-0000-0000000000ff', 'rp-other', 'Other Plan', 'd', 2, 'starter', true,  now());
insert into public.reading_plan_days (id, plan_id, day_number, title, scripture_reference, reflection_body, reflection_prompt) values
  ('00000000-0000-0000-0000-0000000d0b01', '00000000-0000-0000-0000-0000000d0a01', 1, 'D1', 'John 1', 'body', 'prompt'),
  ('00000000-0000-0000-0000-0000000d0b02', '00000000-0000-0000-0000-0000000d0a01', 2, 'D2', 'John 2', 'body', 'prompt');

-- Ada subscribes and completes day 1 (shared with discipler) + day 2 (private).
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.subscribe_to_plan('00000000-0000-0000-0000-0000000d0a01') as rp_sub \gset
select public.complete_plan_day('00000000-0000-0000-0000-0000000d0b01', 'my shared reflection', true);
select public.complete_plan_day('00000000-0000-0000-0000-0000000d0b02', 'my private reflection', false);
reset role;

-- 1. Unpublished plan invisible to a parish member (Bode).
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.reading_plans where id = '00000000-0000-0000-0000-0000000d0a02'), 'RP1: unpublished plan invisible to members');
-- 3. A member cannot see another user's subscription.
select public.t_assert((select count(*) = 0 from public.reading_plan_subscriptions where id = :'rp_sub'), 'RP3: member cannot see another user''s subscription');
reset role;

-- 2. Published plan of ANOTHER parish invisible to a CCCFSP member (Ada).
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.reading_plans where id = '00000000-0000-0000-0000-0000000d0a03'), 'RP2: other-parish published plan invisible');
-- 4. A user CAN see their own subscription.
select public.t_assert((select count(*) = 1 from public.reading_plan_subscriptions where id = :'rp_sub'), 'RP4: user sees own subscription');
-- 8. subscribe_to_plan is idempotent.
select public.t_assert(public.subscribe_to_plan('00000000-0000-0000-0000-0000000d0a01') = :'rp_sub', 'RP8: subscribe_to_plan is idempotent');
reset role;

-- 5/6. Discipler (Disc) sees the SHARED reflection but not the private one.
select set_config('request.jwt.claim.sub', '0e000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.reading_plan_progress where subscription_id = :'rp_sub' and day_id = '00000000-0000-0000-0000-0000000d0b01'), 'RP5: discipler sees shared reflection');
select public.t_assert((select count(*) = 0 from public.reading_plan_progress where subscription_id = :'rp_sub' and day_id = '00000000-0000-0000-0000-0000000d0b02'), 'RP6: discipler cannot see unshared reflection');
reset role;

-- 7. House leader (Tope, Berea leader) cannot see ANY reading-plan progress.
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.reading_plan_progress where subscription_id = :'rp_sub'), 'RP7: house leader cannot see reading-plan progress');
reset role;

-- ===========================================================================
-- 12. GIVING (V2.1) — privacy: giver sees own, admins see parish, no peeking
-- ===========================================================================
reset role;
insert into public.donations (id, parish_id, user_id, fund_id, amount_kobo, kind, status, paystack_reference)
  select '00000000-0000-0000-0000-0000000d0c01', '00000000-0000-0000-0000-000000000001', :'ada',
         (select id from public.giving_funds where parish_id='00000000-0000-0000-0000-000000000001' and slug='tithe'),
         500000, 'one_time', 'success', 'ps_ada_1';
insert into public.donations (id, parish_id, user_id, fund_id, amount_kobo, kind, status, paystack_reference)
  select '00000000-0000-0000-0000-0000000d0c02', '00000000-0000-0000-0000-000000000001', :'bode',
         (select id from public.giving_funds where parish_id='00000000-0000-0000-0000-000000000001' and slug='offering'),
         300000, 'one_time', 'success', 'ps_bode_1';
insert into public.giving_recurring (id, parish_id, user_id, fund_id, amount_kobo, interval, status)
  select '00000000-0000-0000-0000-0000000d0d01', '00000000-0000-0000-0000-000000000001', :'ada',
         (select id from public.giving_funds where parish_id='00000000-0000-0000-0000-000000000001' and slug='tithe'),
         500000, 'monthly', 'active';
insert into public.paystack_events (event_type, reference, payload, signature_valid, processed)
  values ('charge.success', 'ps_ada_1', '{}'::jsonb, true, true);

-- Ada (giver)
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select count(*) = 4 from public.giving_funds), 'GV1: member sees active parish funds');
select public.t_assert((select count(*) = 1 from public.donations where id = '00000000-0000-0000-0000-0000000d0c01'), 'GV2: giver sees own donation');
select public.t_assert((select count(*) = 0 from public.donations where id = '00000000-0000-0000-0000-0000000d0c02'), 'GV3: giver cannot see another member''s donation');
select public.t_assert((select count(*) = 1 from public.giving_recurring where id = '00000000-0000-0000-0000-0000000d0d01'), 'GV4: giver sees own recurring mandate');
select public.t_assert((select count(*) = 0 from public.paystack_events), 'GV5: member cannot read webhook events');
reset role;

-- Pastor (finance admin) sees parish records
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.t_assert((select count(*) = 2 from public.donations where parish_id = '00000000-0000-0000-0000-000000000001'), 'GV6: parish admin sees all parish donations');
select public.t_assert((select count(*) >= 1 from public.paystack_events), 'GV7: parish admin can audit webhook events');
reset role;

-- ===========================================================================
-- 13. MEMBERSHIP GATING (0025) — self-escalation lock + approval + visibility
-- ===========================================================================

-- Self-escalation is blocked: a member cannot change their own role or status.
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);  -- Ada (member, active)
set local role authenticated;
do $esc1$ begin
  update public.user_profiles set role = 'admin' where auth_id = '0a000000-0000-0000-0000-000000000001';
  perform public.t_assert(false, 'GATE1 expected a block but the role update succeeded');
exception when others then
  perform public.t_assert(sqlerrm like '%not user-editable%', 'GATE1: cannot self-escalate role');
end $esc1$;
do $esc2$ begin
  update public.user_profiles set status = 'suspended' where auth_id = '0a000000-0000-0000-0000-000000000001';
  perform public.t_assert(false, 'GATE2 expected a block but the status update succeeded');
exception when others then
  perform public.t_assert(sqlerrm like '%not user-editable%', 'GATE2: cannot change own status');
end $esc2$;
-- A member CAN still edit a normal profile field.
update public.user_profiles set dept = 'Computer Science' where auth_id = '0a000000-0000-0000-0000-000000000001';
select public.t_assert((select dept = 'Computer Science' from public.user_profiles where auth_id = '0a000000-0000-0000-0000-000000000001'), 'GATE3: member can still edit non-protected fields');
reset role;

-- Pending member is hidden from other members' directory.
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);  -- Bode (active)
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.user_profiles where id = :'pend'), 'GATE4: pending member hidden from directory');
select public.t_assert((select count(*) = 0 from public.user_profiles where id = :'susp'), 'GATE4b: suspended member hidden from a student directory');
reset role;

-- Pending member sees only themselves and can read no parish chat.
select set_config('request.jwt.claim.sub', '0f111111-0000-0000-0000-000000000099', true);  -- Pending Pat
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.user_profiles where auth_id = '0f111111-0000-0000-0000-000000000099'), 'GATE5: pending member sees self');
select public.t_assert((select count(*) = 0 from public.chats where kind = 'announcements'), 'GATE6: pending member cannot read parish chat');
reset role;

-- Parish admin CAN see pending signups (approval queue) + list_pending_members.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);  -- Pastor (admin)
set local role authenticated;
select public.t_assert((select count(*) >= 1 from public.user_profiles where status = 'pending'), 'GATE6b: admin sees pending signups');
select public.t_assert((select count(*) >= 1 from public.list_pending_members()), 'GATE6c: list_pending_members returns the queue');
select public.t_assert((select count(*) = 1 from public.user_profiles where id = :'susp'), 'GATE6d: parish admin sees a suspended in-parish member (0033 leader directory)');
reset role;

-- Non-admin cannot approve.
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);  -- Bode (not admin)
set local role authenticated;
do $ap$ begin
  perform public.approve_member(
    (select id from public.user_profiles where auth_id = '0f111111-0000-0000-0000-000000000099'),
    '00000000-0000-0000-0000-0000000ca401');
  perform public.t_assert(false, 'GATE7 expected a block but approve succeeded');
exception when others then
  perform public.t_assert(sqlerrm like '%not authorized%', 'GATE7: non-admin cannot approve members');
end $ap$;
reset role;

-- Pastor can NO LONGER approve (0028 narrowed approve to role='admin').
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);  -- Pastor
set local role authenticated;
do $pa$ begin
  perform public.approve_member(
    (select id from public.user_profiles where auth_id = '0f111111-0000-0000-0000-000000000099'),
    '00000000-0000-0000-0000-0000000ca401');
  perform public.t_assert(false, 'GATE7b expected a block: pastor cannot approve');
exception when others then
  perform public.t_assert(sqlerrm like '%not authorized%', 'GATE7b: pastor cannot approve (admin-only)');
end $pa$;
reset role;

-- A plain admin (role='admin', not owner) approves -> active + campus + parish.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-0000000000ab', true);  -- Plain Admin
set local role authenticated;
select public.approve_member(:'pend', '00000000-0000-0000-0000-0000000ca401');
reset role;
select public.t_assert(
  (select status = 'active' and campus_id = '00000000-0000-0000-0000-0000000ca401'
          and parish_id = '00000000-0000-0000-0000-000000000001'
   from public.user_profiles where id = :'pend'),
  'GATE8: admin approve activates + assigns campus/parish');

-- set_my_campus (0026): an active member with null campus picks once.
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);  -- Bode (active, campus null)
set local role authenticated;
select public.set_my_campus('00000000-0000-0000-0000-0000000ca401');  -- Oye
select public.t_assert((select campus_id = '00000000-0000-0000-0000-0000000ca401' from public.user_profiles where auth_id = '0b000000-0000-0000-0000-000000000002'), 'GATE9: set_my_campus sets campus once');
do $c$ begin
  perform public.set_my_campus('00000000-0000-0000-0000-0000000ca402');  -- Ikole
  perform public.t_assert(false, 'GATE10 expected a block on second set');
exception when others then
  perform public.t_assert(sqlerrm like '%already set%', 'GATE10: campus cannot be changed once set');
end $c$;
reset role;

-- Cross-parish campus is rejected.
insert into public.campuses (id, parish_id, slug, name)
  values ('00000000-0000-0000-0000-0000000ca4ff', '00000000-0000-0000-0000-0000000000ff', 'other', 'Other Campus')
  on conflict (parish_id, slug) do nothing;
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);  -- Tope (cccfsp, campus null)
set local role authenticated;
do $x$ begin
  perform public.set_my_campus('00000000-0000-0000-0000-0000000ca4ff');
  perform public.t_assert(false, 'GATE11 expected a cross-parish block');
exception when others then
  perform public.t_assert(sqlerrm like '%not in your parish%', 'GATE11: cannot pick a campus outside your parish');
end $x$;
reset role;

-- Reports inbox: admin resolve via resolve_report; non-admin blocked.
reset role;
insert into public.reports (id, parish_id, reporter_id, target_type, target_id, reason)
  values ('00000000-0000-0000-0000-0000000d0e01', '00000000-0000-0000-0000-000000000001', :'bode',
          'message', '00000000-0000-0000-0000-0000000ddead', 'test report');
select set_config('request.jwt.claim.sub', '0b000000-0000-0000-0000-000000000002', true);  -- Bode (non-admin)
set local role authenticated;
do $r$ begin
  perform public.resolve_report('00000000-0000-0000-0000-0000000d0e01', 'resolved');
  perform public.t_assert(false, 'GATE12 expected a block on non-admin resolve');
exception when others then
  perform public.t_assert(sqlerrm like '%not authorized%', 'GATE12: non-admin cannot resolve reports');
end $r$;
reset role;
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-0000000000ab', true);  -- Plain Admin
set local role authenticated;
select public.resolve_report('00000000-0000-0000-0000-0000000d0e01', 'resolved');
reset role;
select public.t_assert((select status = 'resolved' and resolved_by is not null and resolved_at is not null
                        from public.reports where id = '00000000-0000-0000-0000-0000000d0e01'),
                       'GATE13: admin resolves a report (stamped)');

-- Owner-only grants admin (0028): a non-owner admin cannot create admins.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-0000000000ab', true);  -- Plain Admin (not owner)
set local role authenticated;
do $ga$ begin
  update public.user_profiles set role = 'admin' where auth_id = '0f000000-0000-0000-0000-000000000006';
  perform public.t_assert(false, 'GATE14 expected a block: non-owner cannot grant admin');
exception when others then
  perform public.t_assert(sqlerrm like '%only an owner%', 'GATE14: non-owner admin cannot grant admin');
end $ga$;
reset role;
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-0000000000aa', true);  -- Owner
set local role authenticated;
update public.user_profiles set role = 'admin' where auth_id = '0f000000-0000-0000-0000-000000000006';
reset role;
select public.t_assert((select role = 'admin' from public.user_profiles where auth_id = '0f000000-0000-0000-0000-000000000006'), 'GATE15: owner can grant admin');

-- ===========================================================================
-- 14. LIBRARY / MEDIA HUB (0031) - published-in-parish reads; admin-only writes
-- ===========================================================================
-- Pastor (admin) creates a published + a draft item in the parish.
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);  -- Pastor
set local role authenticated;
insert into public.library_items (parish_id, kind, title, published, published_at, author_id)
  values ('00000000-0000-0000-0000-000000000001', 'manual', 'September 2026 Manual', true, now(), :'pastor')
  returning id as lib_pub \gset
insert into public.library_items (parish_id, kind, title, published)
  values ('00000000-0000-0000-0000-000000000001', 'audio', 'Draft Sermon', false)
  returning id as lib_draft \gset
select public.t_assert((select count(*) = 1 from public.library_items where id = :'lib_draft'), 'LIB1: admin sees own draft');
reset role;

-- Member: sees the published item, never the draft.
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);  -- Ada (member)
set local role authenticated;
select public.t_assert((select count(*) = 1 from public.library_items where id = :'lib_pub'), 'LIB2: member sees published item');
select public.t_assert((select count(*) = 0 from public.library_items where id = :'lib_draft'), 'LIB3: member cannot see draft');
do $lib$ begin
  insert into public.library_items (parish_id, kind, title)
    values ('00000000-0000-0000-0000-000000000001', 'book', 'Unauthorized');
  perform public.t_assert(false, 'LIB4 expected a block: member cannot insert');
exception when others then
  perform public.t_assert(true, 'LIB4: member cannot write library items');
end $lib$;
reset role;

-- Parish isolation: an other-parish member sees nothing.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);  -- other parish
set local role authenticated;
select public.t_assert((select count(*) = 0 from public.library_items where id = :'lib_pub'), 'LIB5: other-parish member cannot see the item');
reset role;

rollback;
