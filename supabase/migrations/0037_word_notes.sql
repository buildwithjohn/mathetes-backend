-- Private reflections attached to a Word of the Day.
create table if not exists public.word_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  word_of_day_id uuid not null references public.word_of_day(id) on delete cascade,
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, word_of_day_id)
);

create index if not exists idx_word_notes_user on public.word_notes (user_id, updated_at desc);
alter table public.word_notes enable row level security;

create policy "word_notes_own" on public.word_notes for all to authenticated
  using (user_id = public.current_profile_id())
  with check (user_id = public.current_profile_id());

drop trigger if exists trg_word_notes_updated_at on public.word_notes;
create trigger trg_word_notes_updated_at before update on public.word_notes
  for each row execute function public.set_updated_at();
