-- Minimal Supabase environment stubs for local migration smoke-testing.
create extension if not exists pgcrypto;

do $$ begin
  create role anon nologin noinherit;
exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin noinherit;
exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null; end $$;
do $$ begin
  create role supabase_auth_admin noinherit;
exception when duplicate_object then null; end $$;

create schema if not exists auth authorization supabase_auth_admin;
create schema if not exists extensions;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- auth.uid() reads the JWT sub claim from a GUC (set per-session in tests).
create or replace function auth.uid() returns uuid
  language sql stable as $fn$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$fn$;

create or replace function auth.role() returns text
  language sql stable as $fn$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'authenticated');
$fn$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;
