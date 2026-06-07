-- 0008_ask_pastor.sql
-- Ask Pastor: a structured queue (NOT a free chat). A disciple submits a
-- question; the pastor answers within the response window, either privately
-- (to the asker) or publicly (anonymized into the public Q&A feed).

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.ask_questions (
  id                uuid primary key default gen_random_uuid(),
  parish_id         uuid not null references public.parishes(id) on delete cascade,
  asker_id          uuid not null references public.user_profiles(id) on delete cascade,
  body              text not null,
  category          text,
  privacy           text not null default 'private'
                      check (privacy in ('public', 'private')),
  urgent            boolean not null default false,
  status            text not null default 'awaiting'
                      check (status in ('awaiting', 'answered')),
  response_body     text,
  answered_by       uuid references public.user_profiles(id) on delete set null,
  answered_at       timestamptz,
  public_anonymized boolean not null default true,
  created_at        timestamptz not null default now()
);

create index if not exists idx_ask_questions_parish_status on public.ask_questions (parish_id, status, created_at desc);
create index if not exists idx_ask_questions_asker on public.ask_questions (asker_id, created_at desc);
create index if not exists idx_ask_questions_public
  on public.ask_questions (parish_id, answered_at desc)
  where status = 'answered' and privacy = 'public';

-- ---------------------------------------------------------------------------
-- Public Q&A feed: answered, public questions with the asker anonymized.
-- This is a SECURITY DEFINER view (the default): it reads the base table as the
-- view owner and exposes ONLY non-identifying columns, scoped to the caller's
-- parish. This is deliberate: the base table never grants other members a row
-- that carries asker_id, so "public" truly means anonymized.
-- ---------------------------------------------------------------------------

create or replace view public.public_qa as
  select
    id,
    parish_id,
    category,
    body          as question,
    response_body as answer,
    answered_at
  from public.ask_questions
  where status = 'answered'
    and privacy = 'public'
    and parish_id = public.current_parish_id();

grant select on public.public_qa to authenticated;

-- ---------------------------------------------------------------------------
-- answer_question(): pastor/admin answers a question atomically.
-- ---------------------------------------------------------------------------

create or replace function public.answer_question(
  p_id text,
  p_response text,
  p_public boolean default false
)
returns public.ask_questions
language plpgsql
security definer
set search_path = public
as $$
declare
  q public.ask_questions;
begin
  if not public.is_parish_admin() then
    raise exception 'only pastor/admin may answer questions';
  end if;

  update public.ask_questions
    set response_body = p_response,
        privacy       = case when p_public then 'public' else 'private' end,
        status        = 'answered',
        answered_by   = public.current_profile_id(),
        answered_at   = now()
    where id = p_id::uuid
      and parish_id = public.current_parish_id()
    returning * into q;

  if q.id is null then
    raise exception 'question not found in your parish';
  end if;
  return q;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.ask_questions enable row level security;

-- Asker sees their own questions (any status).
create policy "ask_questions_select_own" on public.ask_questions for select
  to authenticated
  using (asker_id = public.current_profile_id());

-- Parish admins (pastor/admin) see the whole queue for their parish.
create policy "ask_questions_select_admin" on public.ask_questions for select
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id());

-- NOTE: there is deliberately no base-table policy exposing public questions to
-- other members. The anonymized public Q&A feed is served by the public_qa view
-- above, so asker identity never leaks through the raw row.

-- Asker submits their own question (always starts unanswered).
create policy "ask_questions_insert_own" on public.ask_questions for insert
  to authenticated
  with check (
    asker_id = public.current_profile_id()
    and parish_id = public.current_parish_id()
    and status = 'awaiting'
    and response_body is null
  );

-- Asker may withdraw a still-unanswered question.
create policy "ask_questions_delete_own" on public.ask_questions for delete
  to authenticated
  using (asker_id = public.current_profile_id() and status = 'awaiting');

-- Pastor/admin answer (update) questions in their parish.
create policy "ask_questions_update_admin" on public.ask_questions for update
  to authenticated
  using (public.is_parish_admin() and parish_id = public.current_parish_id())
  with check (public.is_parish_admin() and parish_id = public.current_parish_id());
