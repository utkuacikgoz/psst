-- Why Psst+ verification failed: one line per failure (the step and Apple's
-- reason, never a proof, key or account). Server-only; read by the
-- diagnose-purchases workflow. Keeps the last 500 lines, at most 7 days.
create table private.purchase_failures (
    id bigserial primary key,
    at timestamptz not null default now(),
    stage text not null,
    reason text not null
);
revoke all on private.purchase_failures from public, anon, authenticated;

create function public.log_purchase_failure(p_stage text, p_reason text) returns void
language sql security definer set search_path = '' as $$
    insert into private.purchase_failures (stage, reason) values (left(p_stage, 40), left(p_reason, 500));
    delete from private.purchase_failures
    where at < now() - interval '7 days'
       or id <= (select max(id) - 500 from private.purchase_failures);
$$;

create function public.recent_purchase_failures() returns table (at timestamptz, stage text, reason text)
language sql security definer set search_path = '' as $$
    select f.at, f.stage, f.reason from private.purchase_failures f order by f.id desc limit 50;
$$;

revoke execute on function public.log_purchase_failure(text, text), public.recent_purchase_failures()
    from public, anon, authenticated;
grant execute on function public.log_purchase_failure(text, text), public.recent_purchase_failures()
    to service_role;
