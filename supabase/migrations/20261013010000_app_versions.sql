-- Which app versions people run, and which ones may still connect.

-- One row: the oldest build allowed to connect, and the newest one out.
-- Change these in the SQL editor; no app release needed:
--   update public.app_config set min_build = 24;                       -- force
--   update public.app_config set latest_build = 25, latest_version = '1.0.5';  -- suggest
create table public.app_config (
    id int primary key default 1 check (id = 1),
    min_build int not null default 0,
    latest_build int not null default 0,
    latest_version text
);
insert into public.app_config default values;
alter table public.app_config enable row level security;
revoke all on public.app_config from public, anon, authenticated;

-- Readable before sign-in, so even onboarding can show "Update Psst".
create function public.app_requirements() returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('min_build', min_build, 'latest_build', latest_build,
                              'latest_version', latest_version)
    from public.app_config where id = 1;
$$;
revoke execute on function public.app_requirements() from public;
grant execute on function public.app_requirements() to anon, authenticated;

-- The version each account last opened Psst with: a version number, nothing else.
-- Not readable by other people (profiles grants only id and display_name).
alter table public.profiles
    add column app_version text,
    add column app_build int,
    add column app_seen_at timestamptz;

create function public.report_app_version(p_version text, p_build int) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    if p_version is null or char_length(p_version) > 20 or p_build is null or p_build < 0 then
        raise exception 'invalid_version' using errcode = 'PT422';
    end if;
    update public.profiles set app_version = p_version, app_build = p_build, app_seen_at = now()
    where id = me;
end;
$$;
revoke execute on function public.report_app_version(text, int) from public, anon, authenticated;
grant execute on function public.report_app_version(text, int) to authenticated;
