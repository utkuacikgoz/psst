# Psst test report

As of 25 September 2026, `main`. "Automated" runs on every push in GitHub Actions; "live" ran against the deployed development backend.

## Verified

| Area | How | Result |
|---|---|---|
| Local preview rules | 12 unit tests (`LocalExchangeTests`): every tap is Psst, unique IDs, idempotent retry, tap coalescing, burst pause and resume, receipt only after display, tap-back | Pass |
| Live app rules | 22 unit tests (`LiveStoreTests`, `LiveParsingTests`) against a fake API: onboarding phases, sign-out, retry reuses the event ID, taps ignored while sending, rate-limit and ended-connection handling, acknowledge only while visible, idempotent notification reply, account deletion, timestamp / row / error / payload / invite-link parsing | Pass |
| Database authorization | 24 tests on real Postgres with row-level security: invite statuses (pending, own, used, already connected, revoked, expired, invalid), mutual connection, send only on your own connection, event-ID hijack refused, unknown or paid effect refused, rate limits, recipient-only acknowledgement, per-side favorites, other pairs invisible, direct writes denied, anonymous role denied, push functions server-only, block / unblock, report (records once a day and blocks; unreadable by clients), remove, device-token move and cleanup, token cap, cascading deletion, 30-day purge | Pass |
| Push function | 15 Deno tests: ES256 provider token verifies, token reuse window, APNs hosts and headers, error-reason parsing, dead-token classification, per-device outcomes, no re-push once accepted, handler auth and validation | Pass |
| Deployed backend | `scripts/smoke_live.py`, 20 checks with throwaway accounts: unauthenticated send refused, invite create / preview / accept / used, send accepted with "no devices" (never "delivered"), same-ID retry is a duplicate, stranger can't send or see, recipient-only seen, account deletion | Pass |
| Screens | UI tests on iPhone SE and iPhone 17 Pro Max at standard and largest accessibility text: local demo (10 states) and live screens against a Debug-only scripted backend (14 states). Images on the `screenshots` branch | Pass, reviewed |
| Build and distribution | Xcode 26 archive, automatic signing through the App Store Connect API, upload to App Store Connect (TestFlight build 4) | Accepted by Apple |

## Not yet verified

- **Push on physical devices:** notification arrival, opening to the right person, "Psst back" from the notification, the "seen" round trip, and the notifications-off path. Needs the two-phone check in `supabase/README.md`.
- **VoiceOver:** labels, hints and actions are set in code, but no one has done a full pass with VoiceOver running.
- **Reduce Motion:** the effect falls back to a fade in code, but it hasn't been reviewed on screen.
- **Offline behaviour on a real network:** simulated offline only.
- **Purchases:** none exist yet.

## Known gaps

- **Reports** are stored and block the person. The owner reviews them regularly by hand (`docs/REPORTS.md`); there is no automated alert.
- The **app icon** is provisional (wordmark on purple).
- Push delivery is only as good as APNs acceptance, which isn't device receipt. The app says "seen" only after the recipient's app displayed the signal.
