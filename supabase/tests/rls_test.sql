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

-- DM: participant reads; house leader oversees (read-only); pastor & outsiders
-- cannot, and cannot even see DM existence.
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.t_assert((select public.can_read_chat(:'dm')), 'DM: participant (Ada) can read');
reset role;

select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.t_assert((select public.can_read_chat(:'dm')), 'DM: house leader (Tope) has oversight read');
select public.t_assert((select not public.can_post_chat(:'dm')), 'DM: oversight is read-only (Tope cannot post)');
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
select public.t_assert((select count(*) = 7 from public.houses), 'Isolation: CCCFSP member sees 7 houses');
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
select public.t_assert((select count(*) = 66 from public.bible_books), 'Bible: readable across parishes (66 books)');
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

rollback;
