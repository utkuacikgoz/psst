# Psst backend (Supabase)

Postgres with row-level security, plus two edge functions. Nothing here holds a
secret; credentials live in Supabase project secrets and in the git-ignored
`Config/Secrets.xcconfig`.

| Path | What it is |
|---|---|
| `migrations/20260924000000_init.sql` | Schema, RLS policies, and every client-callable function |
| `functions/send-signal` | Stores a signal as the caller, then hands it to APNs |
| `functions/delete-account` | Deletes the caller's auth user; everything else cascades |
| `functions/_shared` | APNs client (token auth), delivery logic, HTTP helpers |
| `tests/test_backend.py` | 24 authorization, dedupe, invite, block, token and deletion tests |
| `functions/tests` | 15 Deno tests for APNs signing, delivery outcomes, and the handler |
| `config.toml` | Local CLI config (anonymous sign-ins on) |

## Model

- **profiles**: display name only.
- **invites**: one-use code, 7-day expiry, revocable. Accepting creates the
  connection, so both people have agreed: one by inviting, one by accepting.
- **connections**: one row per pair, with each side's favorite signal.
- **blocks**: blocking deletes the connection and makes either person's invites
  look invalid to the other. The blocked person isn't told.
- **reports**: reporter, reported person and time; `report_user` also blocks.
  Clients can't read the table. Rows go when either account is deleted.
  The owner reviews them regularly: see `docs/REPORTS.md`.
- **signal_events**: the ID is generated on the sending phone and reused on
  retry, so a retry can never store a second copy. `created_at` is server time.
  `seen_at` is set only by the recipient's app after it displayed the signal.
  `push_status` records the APNs hand-off and never means delivery.
- **device_tokens**: a token belongs to whoever registered it last. Tokens APNs
  reports as dead (410, `BadDeviceToken`, `DeviceTokenNotForTopic`) are deleted.

Clients can only `select` their own rows. Every write goes through a
`security definer` function that derives the caller from `auth.uid()` and never
takes "who am I" as a parameter. `push_targets` and `record_push_result` can be
called only with the service role.

Limits enforced in the database: 10 signals a minute to one person, 30 a minute
overall, 5 open invites, 10 device tokens per person. Errors come back as HTTP
status plus a code (`not_connected`, `rate_limited`, `invite_expired`, …).

Retention: signals 30 days, finished invites 30 days. The second migration
schedules `private.purge_expired()` daily with pg_cron (available on Supabase;
skipped on plain Postgres).

## Run the tests

```sh
# Database: any Postgres 15+ where the user can create databases
pip install "psycopg[binary]"
PSST_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/postgres \
  python3 supabase/tests/test_backend.py

# Functions
cd supabase/functions && deno task test && deno task check
```

`tests/auth_shim.sql` stands in for Supabase's `auth` schema and roles so the
tests run on plain Postgres. `.github/workflows/backend.yml` runs both suites.

## Set up a development project

Use separate Supabase projects for development and production, each with its
own keys. None of this costs money on Supabase's free tier. The Apple Developer
membership needed for push is the only paid part.

### One-time setup (you)

1. Create a Supabase project for development.
2. **Authentication → Sign In / Providers**: turn on **Allow anonymous sign-ins**.
3. Create an access token at supabase.com/dashboard/account/tokens.
4. In Apple Developer → Keys, create a key with **Apple Push Notifications
   service**. Note its Key ID and your Team ID. Register a bundle ID you own.
5. In GitHub → this repo → Settings → Secrets and variables → Actions, add:

   | Secret | Value |
   |---|---|
   | `SUPABASE_ACCESS_TOKEN` | the token from step 3 |
   | `SUPABASE_PROJECT_REF` | the `xxxx` in `xxxx.supabase.co` |
   | `SUPABASE_DB_PASSWORD` | the project's database password |
   | `APNS_TEAM_ID` | 10-character team ID |
   | `APNS_KEY_ID` | 10-character key ID |
   | `APNS_BUNDLE_ID` | e.g. `com.yourname.psst` |
   | `APNS_PRIVATE_KEY` | the full text of the `.p8` file, including the BEGIN/END lines |

   Keep the `.p8` file itself out of the repository (`*.p8` is git-ignored).

### Deploy

Run **Actions → Deploy backend (development) → Run workflow**. It:

1. runs the database and function tests,
2. links the project and applies migrations (`supabase db push`),
3. sets the APNs function secrets without printing them,
4. deploys `send-signal` and `delete-account`,
5. runs `scripts/smoke_live.py` against the deployed project: three throwaway
   anonymous accounts invite, connect, send, retry (checked to be a
   duplicate), are refused on someone else's connection, acknowledge, and are
   deleted. It sends no push, since the test accounts have no devices.

Running it again is safe: migrations apply once, and the rest is replaced.

### Point the app at it

Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` on your Mac
and fill in the project host, the anon (publishable) key, your team, and the
same bundle ID as `APNS_BUNDLE_ID`. Builds run from Xcode register **sandbox**
tokens and Release builds register **production** tokens. The function sends
each token to the matching APNs host.

### Without GitHub

The same steps by hand, with the Supabase CLI:

```sh
supabase link --project-ref <ref>
supabase db push
supabase secrets set APNS_TEAM_ID=… APNS_KEY_ID=… APNS_BUNDLE_ID=… \
  APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
supabase functions deploy send-signal
supabase functions deploy delete-account
SUPABASE_PROJECT_REF=<ref> SUPABASE_ANON_KEY=<anon key> python3 scripts/smoke_live.py
```

For a fully local stack, `supabase start` (Docker) applies the migrations, and
`supabase functions serve --env-file supabase/functions/.env` runs the
functions with the APNs variables from that git-ignored file.

## Two-device check (not yet run)

Push delivery, notification actions, and routing after a tap can only be
verified on physical iPhones. Run this with two phones, each signed in to a
different Apple ID or at least a different Psst account:

1. Phone A: enter a name, allow notifications, **+** → **Create invite** → share.
2. Phone B: open the link (or enter the code) → **Connect with A**. Both home
   screens now show the other person.
3. A taps B's row: **Sending…**, then **Sent**. B gets a notification titled
   with A's name. Until B opens it, A's row says "Psst · sent".
4. B taps the notification: Psst opens and plays the signal on A's row. Within
   15 seconds A's row says "Psst · seen".
5. B long-presses a new notification → **Psst back**, without opening the app.
   A receives it.
6. Airplane mode on A, tap B: **Not sent · Retry**. Airplane mode off, tap
   again: exactly one signal arrives.
7. B turns notifications off in Settings, and A sends. B opens Psst: the
   notice explains notifications are off, and the signal plays on A's row.
8. Tap more than 10 times in a minute: **Paused after several taps**.
9. B blocks A: A's next tap removes the row with "You're no longer connected".
10. Delete the account on one phone: the other phone's list no longer shows it.

## Known limits

- **Identity** is an anonymous Supabase account plus a display name. The
  session stays in this phone's Keychain (this device only), so moving to a
  new phone starts a new account. Sign in with Apple is the planned upgrade.
- **Invite links** use the `psst://` scheme. Universal links need a domain
  and are deferred. A link only reveals the inviter's name; nothing happens
  until the recipient taps **Connect**.
- **Seen updates** reach the sender by polling every 15 seconds while the
  app is open. There is no realtime subscription yet.
- **No offline queue.** A signal that didn't reach the server shows
  **Not sent · Retry** on its row until tapped again. It is never sent later
  on its own, and the state is lost if the app is closed.
- **Unverified.** APNs requests are built from Apple's documentation and
  tested against fakes. They haven't reached a real device yet.
