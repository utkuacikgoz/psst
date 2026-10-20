-- The App Review codes written in docs/APP_REVIEW_NOTES.md are in a public repo, so
-- anyone could use up their joins before a reviewer. Revoke every one of them; from
-- 1.0.8 the release workflow makes random codes that only App Store Connect sees.
update public.invites
set revoked_at = now()
where revoked_at is null
  and code in ('PSSTTEAM', 'PSSTBACK', 'PSSTWAVE', 'PSSTHERE', 'PSSTJOIN', 'PSSTNOW1',
               'PSSTFIVE', 'PSSTCATS', 'PSSTHEY2', 'PSSTYAY3');
