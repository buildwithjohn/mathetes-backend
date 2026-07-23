-- 0050_formation_badges.sql
-- Private milestones for a student's formation journey. These are deliberately
-- not a public score, leaderboard, or comparison surface.

create table if not exists public.formation_badges (
  key text primary key,
  title text not null,
  description text not null,
  icon text not null,
  sort_order integer not null default 0
);

insert into public.formation_badges (key, title, description, icon, sort_order)
values
  ('first_word', 'First light', 'Opened the Word and began.', 'sunrise', 10),
  ('first_reflection', 'Listening heart', 'Saved a personal reflection.', 'heart', 20),
  ('plan_starter', 'On the way', 'Completed a reading-plan day.', 'map', 30),
  ('prayer_partner', 'Faithful in prayer', 'Offered prayer five times.', 'hands', 40),
  ('share_hope', 'Hope shared', 'Shared Scripture or a daily encouragement.', 'send', 50),
  ('practice_together', 'Together', 'Completed a House Quest or Campus Mission.', 'people', 60),
  ('faithful_week', 'Seven returns', 'Showed up on seven different days.', 'calendar', 70)
on conflict (key) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  sort_order = excluded.sort_order;

create table if not exists public.member_badges (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  badge_key text not null references public.formation_badges(key) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key (user_id, badge_key)
);

create index if not exists idx_member_badges_user_earned
  on public.member_badges (user_id, earned_at desc);

alter table public.formation_badges enable row level security;
alter table public.member_badges enable row level security;

drop policy if exists "formation_badges_visible_to_members" on public.formation_badges;
create policy "formation_badges_visible_to_members" on public.formation_badges for select to authenticated
  using (public.is_active_member());

drop policy if exists "member_badges_own" on public.member_badges;
create policy "member_badges_own" on public.member_badges for select to authenticated
  using (public.is_active_member() and user_id = public.current_profile_id());

-- This function is only called by the trusted activity logger. It evaluates
-- the caller's own history and uses conflict-safe inserts, making every badge
-- idempotent even if a device retries an action.
create or replace function public.award_formation_badges(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.member_badges (user_id, badge_key)
  select p_user, badge_key
  from (
    select 'first_word'::text as badge_key
    where exists (
      select 1 from public.formation_activities
      where user_id = p_user and kind = 'word_read'
    )
    union all
    select 'first_reflection'
    where exists (
      select 1 from public.formation_activities
      where user_id = p_user and kind = 'reflection_saved'
    )
    union all
    select 'plan_starter'
    where exists (
      select 1 from public.formation_activities
      where user_id = p_user and kind = 'plan_day_complete'
    )
    union all
    select 'prayer_partner'
    where (select count(*) from public.formation_activities where user_id = p_user and kind = 'prayer_offered') >= 5
    union all
    select 'share_hope'
    where exists (
      select 1 from public.formation_activities
      where user_id = p_user and kind = 'verse_shared'
    )
    union all
    select 'practice_together'
    where exists (
      select 1 from public.formation_activities
      where user_id = p_user and kind in ('quest_complete', 'mission_complete')
    )
    union all
    select 'faithful_week'
    where (select count(distinct occurred_on) from public.formation_activities where user_id = p_user) >= 7
  ) earned
  on conflict (user_id, badge_key) do nothing;
end;
$$;

create or replace function public.record_formation_activity(
  p_kind text,
  p_target_key text default ''
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.current_profile_id();
  v_parish uuid := public.current_parish_id();
begin
  if v_me is null or not public.is_active_member() then
    raise exception 'active membership required';
  end if;
  if p_kind not in (
    'word_read', 'devotional_read', 'plan_day_complete', 'reflection_saved',
    'prayer_offered', 'verse_shared', 'quest_complete', 'mission_complete'
  ) then
    raise exception 'unsupported formation activity';
  end if;

  insert into public.formation_activities (user_id, parish_id, kind, target_key)
  values (v_me, v_parish, p_kind, coalesce(left(p_target_key, 160), ''))
  on conflict (user_id, kind, target_key, occurred_on) do nothing;

  perform public.award_formation_badges(v_me);
end;
$$;

revoke all on table public.member_badges from anon, authenticated;
grant select on table public.member_badges to authenticated;
grant select on table public.formation_badges to authenticated;
revoke all on function public.award_formation_badges(uuid) from public;
revoke all on function public.record_formation_activity(text, text) from public;
grant execute on function public.record_formation_activity(text, text) to authenticated;
