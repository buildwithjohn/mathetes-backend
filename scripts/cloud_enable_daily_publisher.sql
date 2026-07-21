-- One-time Mathetes production setup. Run in Supabase Dashboard → SQL Editor.
-- Invokes the deployed public publisher at 00:01 Africa/Lagos (23:01 UTC).

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'mathetes-daily-content-publish';

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
end;
$$;

select cron.schedule(
  'mathetes-daily-content-publish',
  '1 23 * * *',
  $job$
    select net.http_post(
      url := 'https://jowokfnlfqqjzwhvnmxj.supabase.co/functions/v1/daily-content-publish',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := '{}'::jsonb
    );
  $job$
);

select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'mathetes-daily-content-publish';
