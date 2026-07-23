-- 0047_member_profile_presence.sql
--
-- A small, parish-visible profile layer for real community context. This is
-- deliberately not a public social feed: members write one optional bio and
-- one optional current thought, both visible only wherever their existing
-- active-parish profile is already visible under RLS.

alter table public.user_profiles
  add column if not exists bio text,
  add column if not exists thought text,
  add column if not exists thought_updated_at timestamptz;

alter table public.user_profiles drop constraint if exists user_profiles_bio_length_check;
alter table public.user_profiles add constraint user_profiles_bio_length_check
  check (bio is null or char_length(bio) <= 280);

alter table public.user_profiles drop constraint if exists user_profiles_thought_length_check;
alter table public.user_profiles add constraint user_profiles_thought_length_check
  check (thought is null or char_length(thought) <= 180);

create or replace function public.set_profile_thought_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.thought is distinct from old.thought then
    new.thought := nullif(btrim(coalesce(new.thought, '')), '');
    new.thought_updated_at := case when new.thought is null then null else now() end;
  end if;
  if new.bio is not null then
    new.bio := nullif(btrim(new.bio), '');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profile_thought_updated_at on public.user_profiles;
create trigger trg_profile_thought_updated_at
  before update of bio, thought on public.user_profiles
  for each row execute function public.set_profile_thought_updated_at();
