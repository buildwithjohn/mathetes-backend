-- 0018_campus_houses.sql
-- House fellowships per campus + richer member profile fields.
--
-- Houses now belong to a campus, so a member who picks Oye sees Oye's houses
-- and Ikole sees Ikole's. The original seven houses become Oye's; Ikole gets
-- its own seven (same names, distinct rows + house-group chats). Also adds
-- date_of_birth and phone to user_profiles for the discipleship directory.

-- ---------------------------------------------------------------------------
-- Member profile fields
-- ---------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists date_of_birth date,
  add column if not exists phone text;

-- ---------------------------------------------------------------------------
-- Houses get a campus.
-- ---------------------------------------------------------------------------

alter table public.houses
  add column if not exists campus_id uuid references public.campuses(id) on delete cascade;

create index if not exists idx_houses_campus on public.houses (campus_id);

-- Existing seven houses belong to Oye (the original pilot campus).
update public.houses
  set campus_id = '00000000-0000-0000-0000-0000000ca401'
  where parish_id = '00000000-0000-0000-0000-000000000001' and campus_id is null;

-- Seed Ikole's seven houses (same names, distinct slugs/UUIDs). Adjust if Ikole
-- runs a different set of fellowships.
insert into public.houses (id, parish_id, campus_id, slug, name, color, verse_ref, verse) values
  ('00000000-0000-0000-0000-0ca4020000b1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','bethel-ikole','Bethel House','#B87333','Genesis 28:17','And he was afraid, and said, How dreadful is this place! this is none other but the house of God, and this is the gate of heaven.'),
  ('00000000-0000-0000-0000-0ca4020000a1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','antioch-ikole','Antioch House','#722F37','Acts 11:26','And the disciples were called Christians first in Antioch.'),
  ('00000000-0000-0000-0000-0ca4020000be','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','berea-ikole','Berea House','#A87C3E','Acts 17:11','These were more noble than those in Thessalonica, in that they received the word with all readiness of mind, and searched the scriptures daily, whether those things were so.'),
  ('00000000-0000-0000-0000-0ca4020000b2','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','bethany-ikole','Bethany House','#7A8A6E','John 11:25','Jesus said unto her, I am the resurrection, and the life: he that believeth in me, though he were dead, yet shall he live.'),
  ('00000000-0000-0000-0000-0ca4020000c1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','zion-ikole','Zion House','#C9A24A','Psalm 125:1','They that trust in the LORD shall be as mount Zion, which cannot be removed, but abideth for ever.'),
  ('00000000-0000-0000-0000-0ca4020000d1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','hebron-ikole','Hebron House','#A85838','Psalm 133:1','Behold, how good and how pleasant it is for brethren to dwell together in unity!'),
  ('00000000-0000-0000-0000-0ca4020000e1','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000ca402','salem-ikole','Salem House','#6B7F8A','Hebrews 7:2','To whom also Abraham gave a tenth part of all; first being by interpretation King of righteousness, and after that also King of Salem, which is, King of peace.')
on conflict (parish_id, slug) do nothing;

-- House-group chats for the Ikole houses (so picking one auto-joins its chat).
insert into public.chats (id, kind, parish_id, house_id) values
  ('0000000c-0000-0000-0000-0ca4020000b1','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000b1'),
  ('0000000c-0000-0000-0000-0ca4020000a1','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000a1'),
  ('0000000c-0000-0000-0000-0ca4020000be','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000be'),
  ('0000000c-0000-0000-0000-0ca4020000b2','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000b2'),
  ('0000000c-0000-0000-0000-0ca4020000c1','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000c1'),
  ('0000000c-0000-0000-0000-0ca4020000d1','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000d1'),
  ('0000000c-0000-0000-0000-0ca4020000e1','house_group','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0ca4020000e1')
on conflict (id) do nothing;
