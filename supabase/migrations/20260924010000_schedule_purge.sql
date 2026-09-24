-- Run the retention purge daily where pg_cron is available (it is on Supabase).
-- Plain Postgres without pg_cron (e.g. the test database) skips this.
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        create extension if not exists pg_cron;
        execute $cron$
            select cron.schedule('psst-purge', '17 3 * * *', 'select private.purge_expired()')
        $cron$;
    end if;
end;
$$;
