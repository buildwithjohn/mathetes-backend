-- This is the production-safe equivalent of migration 0041. Apply after
-- `SEND_PUSH_WEBHOOK_SECRET` has been set for the Edge Function and the same
-- value stored in Vault as `mathetes_send_push_webhook`.

create or replace function public.queue_push_delivery()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
begin
  if to_regclass('vault.decrypted_secrets') is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return new; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into v_secret using 'mathetes_send_push_webhook';
  if v_secret is null or v_secret = '' then raise warning 'Mathetes push delivery is not configured: Vault secret is missing'; return new; end if;
  execute 'select net.http_post($1, $2, $3, $4, $5)' using
    'https://jowokfnlfqqjzwhvnmxj.supabase.co/functions/v1/send-push',
    jsonb_build_object('type', 'INSERT', 'table', 'notifications', 'schema', 'public', 'record', to_jsonb(new), 'old_record', null),
    '{}'::jsonb,
    jsonb_build_object('Content-Type', 'application/json', 'x-mathetes-webhook', v_secret),
    5000;
  return new;
end;
$$;
drop trigger if exists trg_queue_push_delivery on public.notifications;
create trigger trg_queue_push_delivery after insert on public.notifications
  for each row execute function public.queue_push_delivery();
