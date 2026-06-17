-- 0024_giving_realtime.sql
-- V2.1 follow-up: let the client live-watch giving outcomes. The mobile app
-- opens the Paystack checkout URL and waits for the backend webhook to settle
-- the gift, so it needs realtime on `donations` (and `giving_recurring` for
-- mandate status). Same tolerant guard as 0006/0010: on hosted Supabase the
-- publication is owned by another role, so a permission error logs a NOTICE
-- instead of aborting (enable from Database > Replication if so).

do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      create publication supabase_realtime;
    exception when others then raise notice 'realtime: could not create publication: %', sqlerrm;
    end;
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['donations','giving_recurring'] loop
    begin
      if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
         and not exists (select 1 from pg_publication_tables
                         where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    exception when others then
      raise notice 'realtime: could not add %: %', t, sqlerrm;
    end;
  end loop;
end $$;
