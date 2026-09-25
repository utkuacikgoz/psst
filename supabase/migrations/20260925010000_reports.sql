-- Report someone (App Store guideline 1.2). Reporting also blocks them, so the
-- reporter is protected immediately. Reports hold no message content: Psst has
-- none. The owner reviews them in the dashboard; clients cannot read them.

create table public.reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles (id) on delete cascade,
    reported_id uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    check (reporter_id <> reported_id)
);
create index reports_reported_idx on public.reports (reported_id);

alter table public.reports enable row level security;
revoke all on public.reports from public, anon, authenticated;

create function public.report_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    if p_user_id is null or p_user_id = me
       or not exists (select 1 from public.profiles where id = p_user_id) then
        raise exception 'invalid_user' using errcode = 'PT422';
    end if;
    -- One open report per pair per day is enough; repeats add nothing.
    if not exists (
        select 1 from public.reports
        where reporter_id = me and reported_id = p_user_id
          and created_at > now() - interval '1 day'
    ) then
        insert into public.reports (reporter_id, reported_id) values (me, p_user_id);
    end if;
    perform public.block_user(p_user_id);
end;
$$;

revoke execute on function public.report_user(uuid) from public, anon, authenticated;
grant execute on function public.report_user(uuid) to authenticated;
