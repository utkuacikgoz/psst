# Psst test report

As of 25 September 2026, `main`. Unit, database and edge-function tests run in GitHub Actions on pushes to `main` that touch them. UI screenshot tests run on demand. "Live" ran against the deployed development backend.

## Verified

| Area | How | Result |
|---|---|---|
| Local preview rules | 10 unit tests (`LocalExchangeTests`): every tap is Psst, unique IDs, idempotent retry, tap coalescing, burst pause and resume, receipt only after display, tap-back | Pass |
| Live app rules | 37 unit tests (`LiveStoreTests`, `LiveParsingTests`, `PsstPlusTests`) against a fake API. They cover onboarding phases and sign-out; retry reusing the event ID; taps ignored while sending; the one-minute pacing pause and countdown; ended connections; acknowledging only while visible; and arrivals queued one after another, newest last. Also: same moment from the send result and the push payload; the welcome shown once to new people only; the invite-link intro and auto-accept; order (most recent first, drag to place, VoiceOver moves, reset); notification status reported only on change; the idempotent notification reply; account deletion; and parsing. Psst+ is covered too: a revoked or refunded purchase doesn't unlock, and colour choices persist on the phone only. | Pass |
| Database authorization | 29 tests on real Postgres with row-level security. Invites: every status (pending, own, used, already connected, revoked, expired, invalid); open invites list only your own usable ones. Connections: mutual acceptance; send only on your own connection; event-ID hijack refused; unknown effects refused; rate limits; recipient-only acknowledgement; other pairs invisible; direct writes denied; anonymous role denied; push functions server-only. Blocking and reports: block / unblock; report (recorded once a day, blocks, unreadable by clients); remove. Same moment: within 10 s, answering the other person only, once a minute. Sound: each recipient chooses their own from an allow-list. Metrics: aggregate counts only, unreadable by clients. Also device-token move and cleanup, the token cap, cascading deletion and the 30-day purge. | Pass |
| Push function | 15 Deno tests: payload carries the chosen sound and the same-moment flag, ES256 provider token verifies, token reuse window, APNs hosts and headers, error-reason parsing, dead-token classification, per-device outcomes, no re-push once accepted, handler auth and validation | Pass |
| Deployed backend | `scripts/smoke_live.py`, 20 checks with throwaway accounts: unauthenticated send refused, invite create / preview / accept / used, send accepted with "no devices" (never "delivered"), same-ID retry is a duplicate, stranger can't send or see, recipient-only seen, account deletion | Pass |
| Screens | UI tests, run on demand as four parallel jobs: iPhone SE and iPhone 17 Pro Max, each at standard and largest accessibility text. They cover the local demo (Alex's side uses the real arrival) and live screens against a Debug-only scripted backend: onboarding, arrival, the tap-and-hold tip, same moment, sending, sent, didn't make it, the dimmed pause, the offline strip, the long-press menu, the report confirmation, the invite chooser, share, code and connect, the welcome, settings with people, and the empty home. Images are on the `screenshots` branch. | Pass, reviewed |
| Build and distribution | Xcode 26 archive, automatic signing through the App Store Connect API, upload to App Store Connect (TestFlight build 4) | Accepted by Apple |

## Not yet verified

- **Push on physical devices:** notification arrival, opening to the right person, "Psst back" from the notification, the "seen" round trip, and the notifications-off path. Needs the two-phone check in `supabase/README.md`.
- **VoiceOver:** labels, hints and actions are set in code, but no one has done a full pass with VoiceOver running.
- **Reduce Motion:** the effect falls back to a fade in code, but it hasn't been reviewed on screen.
- **Offline behaviour on a real network:** simulated offline only.
- **Psst+ purchases:** the StoreKit 2 code is unit-tested for entitlement rules only. Buying, restoring, Ask to Buy and refunds need the `psstplus.unlock` product in App Store Connect and a sandbox tester on a device.
- **Whisper sounds and alternate icons on a device:** push sounds (`psst.wav`, `psst-soft.wav`, `psst-quick.wav`) and icon switching can only be heard or seen on real iPhones.
- **Nightly metrics job:** tested with a direct call. The pg_cron schedule on Supabase will first run the night after deployment.

## Known gaps

- **Reports** are stored and block the person. The owner reviews them regularly by hand (`docs/REPORTS.md`); there is no automated alert.
- The **app icon** is final: the white "psst" wordmark on #713F93, owner-approved. Psst+ adds Night, Gold and Pink versions.
- Push delivery is only as good as APNs acceptance, which isn't device receipt. The app says "seen" only after the recipient's app displayed the signal.
