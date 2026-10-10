# October feature validation

Final local verification:

| Check | Result |
|---|---|
| iOS unit tests | 59 passed |
| PostgreSQL migration/auth/limit tests | 33 passed |
| Deno delivery and purchase-handler tests | 21 passed |
| Deno function type checking | Passed |
| Native feature capture, iPhone 17 Pro | Passed |
| Large-phone layout capture, iPhone 17 Pro Max | Passed |
| Long press → Super review → cancel; one-tap ordinary send | Passed |
| Compact-phone captures at largest accessibility text size | Passed |
| Focused normal/large-text activity, code entry and home checks | Passed |
| Git whitespace check | Passed |

The new tests exercise global daily allowance, simultaneous Super requests,
idempotent retries, purchase ownership and expiry/revocation, ordinary free
notification replies to Super, old-version notification routing, private 30-day
counts, muted Super presentation, introduction persistence and safe retry states.
The latest interaction test checks long-press Super discovery and one-tap ordinary sending.

Visual inspection found and corrected small activity tabs at accessibility text
sizes and invite-code entry shrinking. Inline direction choices appear only at
accessibility sizes; normal-size tabs remain segmented. The latest proposal keeps the home bands clean. Intro, picker and native forms scroll at large text.

Earlier capture attempts hit an ephemeral arrival timeout and a duplicate-name
UI-test query; the corrected captures and recipient selector passed. A combined
unit/capture run was interrupted during a manual app installation; the complete
55-test unit suite subsequently passed separately. These were local validation
issues, not results claimed as passing.

Screenshots are Debug-only fixtures, not real contacts or production exchanges.
See `output/feature-review` in the parent workspace for the approval gallery,
large-device and accessibility captures. The default app still requires its live
backend configuration; fixture data never appears in a normal launch.

Not verified: physical-device APNs delivery/sound, Focus/silent behavior, hardware
haptic feel, actual StoreKit sandbox buy/restore/refund and server credential
configuration. No backend deployment, publication or real purchase was performed.
See `FEATURE_RELEASE.md` for migration/verification setup and the known anonymous
account binding limitation for unlimited purchase restoration on a new account.

A different implementation agent addressed the remaining Apple design audit
findings in `APPLE_DESIGN_AUDIT.md`. Four additional regression tests cover
settings cancellation, unblock and name-save recovery. Physical-device checks
remain recorded in that report.

## Final placement

The owner selected long press for now. Ordinary taps send immediately; touch and
hold a person, then choose Super Psst to open the approved review. The rejected
header, repeated per-person buttons and choice sheet are removed. Prior choice
sheet checks and screenshots are historical, not evidence of the current flow.
The introduction and first-use hint now explain long press. Latest native verification passed: introduction, long-press menu, correct Super
recipient, unused allowance before sending, cancellation and one-tap ordinary
send. Two UI tests passed with zero failures. Result bundle:
`/tmp/psst-long-press-final.xcresult`. Native screenshots refresh the approval gallery.

Largest-text inspection also corrected overlapping seen/timestamp text by giving
seen its own line. Other approved screens and audit fixes remain in place.
