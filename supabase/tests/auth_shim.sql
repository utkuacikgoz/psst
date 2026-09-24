-- Minimal stand-in for Supabase's auth schema and roles, so the migrations and
-- authorization tests run against any plain Postgres 15+. Never apply this to a
-- Supabase project; it already provides the real ones.
do $$ begin
    create role anon nologin;
exception when duplicate_object then null; end $$;
do $$ begin
    create role authenticated nologin;
exception when duplicate_object then null; end $$;
do $$ begin
    create role service_role nologin bypassrls;
exception when duplicate_object then null; end $$;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create table auth.users (id uuid primary key default gen_random_uuid());

create function auth.uid() returns uuid language sql stable as $$
    select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid;
$$;

-- Supabase's default privileges: API roles get table and function access,
-- and RLS plus explicit revokes do the restricting.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
