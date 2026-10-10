# October feature release — implementation and design review

The owner's decisions: latest exchange in either direction; private personal
rankings; subtle mischievous cat; one Super Psst total daily, accessed through a person’s long-press menu; unlimited with the one-time Psst+ unlock; an introduction for users.

## Behavior

- Contact bands show Sent/Received with the latest server timestamp. Minutes
  appear for recent exchanges, then local time, Yesterday, or a local date.
  VoiceOver reads the full date/time. Seen is a separate acknowledgement.
- Settings → Your Psst activity ranks current connections by sent/received
  counts over a rolling 30 days. Both ordinary and Super Pssts count. Only the
  authenticated account can fetch its counts. Zero-count contacts aren't ranked.
- Existing accounts get one dismissible What's new sheet per release. Dismissal
  and Got it persist identically and never send. New accounts get the updated
  first-use tip explaining tap to send and hold for Super Psst. Existing users also get a dismissible contextual Super Psst hint.
- Tapping a person sends an ordinary Psst immediately. Touch and hold a person,
  then choose Super Psst to open its review with availability. Send Super Psst
  remains explicit. VoiceOver provides an equivalent custom action.
- The free allowance is one per account per UTC calendar day, not per contact.
  The server returns the reset time, displayed in the phone's local timezone.
  Quota survives connection deletion and uses a sender transaction lock to prevent
  concurrent requests consuming more than one daily allowance. Idempotent retries
  do not spend a second allowance. Ordinary replies never spend it.
- Existing pacing remains 10/minute to one person and 30/minute overall,
  including paid sends. A failed send retains its event ID and effect on retry.
- Recipient Settings includes optional haptics and Super sounds/effects. Muted
  Super Pssts are pushed and fetched as ordinary Pssts. The sender's allowance
  still counts the Super they chose to send. Focus and silent mode still apply.
- The native vector cat appears on invitations, empty home, introduction, Super
  sheet and arrival. Mischief is an optional Psst+ icon; Purple stays the default.

## Purchase verification and deployment

Deploy `20261011000000_super_psst_activity.sql` and `verify-plus`, together with
`send-signal`. The database never trusts a client boolean for paid sending.

`verify-plus` uses Apple's pinned Node server library 3.1.0 to verify the signed
StoreKit transaction against Apple trust roots, then queries Apple's Server API
for fresh revocation status and verifies that response. Newly bought transactions
use the anonymous account UUID as appAccountToken. Legacy proofs without a token
can be claimed once, enforced by unique original transaction ID. Account-bound
proofs are refused on another account. A verified entitlement is cached for at
most five minutes; expired or revoked entitlements fall back to the daily free
allowance. The app refreshes verification when opening Super and before sending.

Configure these **server secrets**, never app config or source:

- APP_STORE_ENVIRONMENT: Sandbox or Production (no client-selected environment).
- APP_STORE_BUNDLE_ID, APP_STORE_ISSUER_ID, APP_STORE_KEY_ID, APP_STORE_PRIVATE_KEY.
- APP_STORE_APP_ID: required in Production.
- APPLE_ROOT_CA_BASE64: JSON array of base64 DER root certificates from Apple PKI.

Unset secrets fail closed for unlimited sends; daily free sends still work.
Xcode-local StoreKit test transactions are not Apple sandbox transactions and
cannot unlock the server. Use actual StoreKit sandbox transactions to validate.
The existing manual deployment workflow deploys the new endpoint; configure its
App Store secrets in Supabase before testing unlimited sends.

No backend deployment, real purchase, App Store submission or push-device
verification is performed by this local change. Test a two-device send/receive,
Super sound, silent/Focus behavior, muted Super, StoreKit sandbox buy/restore,
refund, and expiry before releasing. Anonymous accounts don't migrate across
phones: account-bound unlimited entitlement restoration requires the original
account. Local cosmetic purchase restoration continues to use StoreKit.

## Apple design review

- Functional titles use system spacing rather than fixed negative tracking.
- Titles wrap; they no longer shrink to 40% to fit.
- Accessibility-sized invitations scroll; codes wrap as two readable groups.
- Introduction and Super sheets scroll using native containers.
- Home rows use Dynamic Type, 44pt controls, labeled VoiceOver actions and
  separate sent/seen feedback. Super has optional short foreground haptics and
  a Reduce Motion-aware visual. No remote custom vibration is promised.

Primary references:
[UI typography](https://developer.apple.com/videos/play/wwdc2020/10175/),
[Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics),
[APNs payload](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification),
[Apple server library](https://github.com/apple/app-store-server-library-node).

## Copy refinement after design review

The owner approved the visual direction and requested warmer, shorter Super
copy. The sheet now says "Give NAME a little nudge." / "A double whisper.
A little mischief." The available state says "Your Super Psst is ready."
The reset timestamp appears only once used, with a small sound-settings note.
The explicit Send Super Psst action and unlimited Psst+ option remain.

The latest approved sheet copy is "Super Psst for NAME" / "Double whisper." /
"1 available today". After reviewing alternative placements, the owner selected
long press for now. The home screen stays clean and ordinary sends remain one
tap. The introduction and first-use tip explain the gesture. The other approved
screens, copy and audit fixes remain in place.

## Validation

Local native build and the 67-test integrated iOS unit suite pass. Backend migration,
authorization, concurrency and entitlement tests: 33 pass. Deno delivery and
purchase-verification handler tests: 21 pass; function type checks pass. Native
normal-size feature captures and Super arrival checks pass. The full validation
report records the remaining device-size checks separately.

## Release 1.0.3 integration

Current main was integrated before release, retaining its widget, additional
whisper sounds, notification setup, cache and startup improvements. App and widget
versions are 1.0.3. The backend workflow configures purchase-verification secrets
using App Store Connect credentials for app metadata, a separate In-App Purchase
key for transaction verification, and Apple’s public root certificate.
Choose Sandbox for TestFlight purchases even when the app uses the production
Supabase backend; choose Production for App Store purchases. Public privacy
disclosures now include daily usage and purchase-verification records.

Integrated iOS unit suite: 67 passed. PostgreSQL and Deno CI checks passed.

### Apple key separation

GitHub secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` are only for
App Store Connect metadata and TestFlight upload. Transaction verification requires
`IAP_KEY_ID`, `IAP_ISSUER_ID`, and `IAP_KEY_P8`, generated under In-App Purchase.
The deployment authenticates this key with a read-only transaction API request.
When it is absent, paid verification fails closed and the free daily allowance
continues to work. The deployment clears stale upload-key values from verifier
configuration. See [Apple’s key guide](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests).
