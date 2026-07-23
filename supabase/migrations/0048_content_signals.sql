-- 0048_content_signals.sql
--
-- A light, parish-scoped encouragement layer for daily Word and devotionals.
-- A member may give one Amen and one share signal per item. We expose totals,
-- never names or a ranked feed, so this reinforces formation without creating
-- social pressure.

create table if not exists public.content_signals (
  id uuid primary key default gen_random_uuid(),
  parish_id uuid not null references public.parishes(id) on delete cascade,
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  content_kind text not null check (content_kind in ('word', 'devotional')),
  content_id uuid not null,
  signal text not null check (signal in ('amen', 'share')),
  created_at timestamptz not null default now(),
  unique (user_id, content_kind, content_id, signal)
);

create table if not exists public.content_signal_counts (
  content_kind text not null check (content_kind in ('word', 'devotional')),
  content_id uuid not null,
  parish_id uuid not null references public.parishes(id) on delete cascade,
  amen_count integer not null default 0 check (amen_count >= 0),
  share_count integer not null default 0 check (share_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (content_kind, content_id)
);

create index if not exists idx_content_signals_content
  on public.content_signals (content_kind, content_id, signal);
create index if not exists idx_content_signal_counts_parish
  on public.content_signal_counts (parish_id, updated_at desc);

alter table public.content_signals enable row level security;
alter table public.content_signal_counts enable row level security;

drop policy if exists "content signal counts visible in parish" on public.content_signal_counts;
create policy "content signal counts visible in parish" on public.content_signal_counts for select to authenticated
  using (public.is_active_member() and parish_id = public.current_parish_id());

-- Validate the target at the database boundary so a client cannot signal a
-- private, future, or cross-parish item by guessing a UUID.
create or replace function public.assert_signalable_content(p_kind text, p_content uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_parish uuid;
  v_today date := timezone('Africa/Lagos', now())::date;
begin
  if not public.is_active_member() then
    raise exception 'active membership required';
  end if;

  if p_kind = 'word' then
    select parish_id into v_parish
    from public.word_of_day
    where id = p_content
      and status in ('published', 'scheduled')
      and publish_date <= v_today;
  elsif p_kind = 'devotional' then
    select parish_id into v_parish
    from public.devotionals
    where id = p_content
      and status in ('published', 'scheduled')
      and (publish_date is null or publish_date <= v_today);
  else
    raise exception 'unsupported content type';
  end if;

  if v_parish is null or v_parish <> public.current_parish_id() then
    raise exception 'content is not available in your parish';
  end if;
  return v_parish;
end;
$$;

create or replace function public.toggle_content_amen(p_kind text, p_content uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid;
  v_deleted uuid;
  v_inserted uuid;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  v_parish := public.assert_signalable_content(p_kind, p_content);

  delete from public.content_signals
  where user_id = v_me and content_kind = p_kind and content_id = p_content and signal = 'amen'
  returning id into v_deleted;

  if v_deleted is not null then
    update public.content_signal_counts
    set amen_count = greatest(amen_count - 1, 0), updated_at = now()
    where content_kind = p_kind and content_id = p_content;
    return false;
  end if;

  insert into public.content_signals (parish_id, user_id, content_kind, content_id, signal)
  values (v_parish, v_me, p_kind, p_content, 'amen')
  on conflict (user_id, content_kind, content_id, signal) do nothing
  returning id into v_inserted;

  if v_inserted is null then return true; end if;

  insert into public.content_signal_counts (content_kind, content_id, parish_id, amen_count)
  values (p_kind, p_content, v_parish, 1)
  on conflict (content_kind, content_id) do update
    set amen_count = public.content_signal_counts.amen_count + 1,
        updated_at = now();
  return true;
end;
$$;

create or replace function public.record_content_share(p_kind text, p_content uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid;
  v_inserted uuid;
  v_count integer;
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  v_parish := public.assert_signalable_content(p_kind, p_content);

  insert into public.content_signals (parish_id, user_id, content_kind, content_id, signal)
  values (v_parish, v_me, p_kind, p_content, 'share')
  on conflict (user_id, content_kind, content_id, signal) do nothing
  returning id into v_inserted;

  if v_inserted is not null then
    insert into public.content_signal_counts (content_kind, content_id, parish_id, share_count)
    values (p_kind, p_content, v_parish, 1)
    on conflict (content_kind, content_id) do update
      set share_count = public.content_signal_counts.share_count + 1,
          updated_at = now();
  end if;

  select coalesce(share_count, 0) into v_count
  from public.content_signal_counts
  where content_kind = p_kind and content_id = p_content;
  return coalesce(v_count, 0);
end;
$$;

create or replace function public.content_signal_summary(p_kind text, p_content uuid)
returns table (amen_count integer, share_count integer, my_amen boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
begin
  if v_me is null then raise exception 'no authenticated profile'; end if;
  perform public.assert_signalable_content(p_kind, p_content);
  return query
  select
    coalesce(c.amen_count, 0),
    coalesce(c.share_count, 0),
    exists (
      select 1 from public.content_signals s
      where s.user_id = v_me and s.content_kind = p_kind and s.content_id = p_content and s.signal = 'amen'
    )
  from (select 1) placeholder
  left join public.content_signal_counts c
    on c.content_kind = p_kind and c.content_id = p_content;
end;
$$;

grant execute on function public.toggle_content_amen(text, uuid) to authenticated;
grant execute on function public.record_content_share(text, uuid) to authenticated;
grant execute on function public.content_signal_summary(text, uuid) to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'content_signal_counts'
  ) then
    alter publication supabase_realtime add table public.content_signal_counts;
  end if;
exception when others then
  raise notice 'realtime: could not add content_signal_counts: %', sqlerrm;
end $$;
