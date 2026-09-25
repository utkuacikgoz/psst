# Psst — standalone Claude Code brief

This repository contains only Psst, a native iPhone one-tap social app. Build the complete app incrementally from the included interaction prototype. No sibling repository, shared package, or other app is required.

## Read first
- `DESIGN.md`: layout, visual tokens, feedback states, preview/purchase rules, and visual acceptance checks.
- `README.md`: build instructions and current prototype limitations.

## Owner decisions
- Revive Yo’s simple one-tap contact idea under a new name.
- **An inside joke between people who care about each other:** warm by default, with optional mischief. Neither an exclusively romantic app nor an exclusively comic app.
- Sending is one tap on the person.
- **One signal: Psst.** The owner removed Squeeze, Oi and Duck on 25 Sep 2026, along with choosing, previewing and per-connection favourite signals. Don't reintroduce other signals or a signal picker without the owner's approval.
- Receivers control sound and notifications.
- **Monetization (owner pick, 25 Sep 2026):** one optional "Psst+" one-time unlock with personal extras only: custom band colours, alternate app icons, a choice of whisper sounds, and later the widget. Sending, receiving, Psst back and invites stay free. The price is a hypothesis ($2.99–$4.99). Build it with StoreKit 2 and sandbox testing only, and ideally after TestFlight shows people returning.
- First prototype: one person, four signals, and the receiving/replying experience.
- Mobile app first, concise updates, careful token use, and exceptional execution without template clutter.

“Psst” is the brand and home-screen name. The App Store listing is **Psst Back: Thinking of You** (owner pick, 25 Sep 2026), because “Psst” alone is taken. Spell it psst, never pst. The owner chose the original Yo as the visual reference after rejecting the cobalt-card design. Follow the revised colour-band direction in DESIGN.md. Paid pack prices remain hypotheses. No revenue or retention assumptions have been validated.

## Existing implementation
Open `Psst.xcodeproj`. It is a native SwiftUI iPhone app, targeting iOS 17+, with no third-party packages. It runs in one of two modes:

- **Local preview** (no configuration): Alex is an explicitly fictional demo connection. The user can trigger a local sender reaction, switch to Alex's recipient preview, and tap back. It must remain visibly labeled local preview and does not establish remote delivery.
- **Live** (when `Config/Secrets.xcconfig` names a Supabase project): anonymous account plus display name, invites, mutual connections, authenticated send through the `send-signal` edge function, APNs push, notification "Psst back", seen acknowledgements, block/remove, and account deletion. The backend is in `supabase/` with migrations and tests. The development backend is deployed through `.github/workflows/deploy-backend.yml` (manual) and passes its live server checks: invites, sending, idempotent retry, authorization refusal, acknowledgement and account deletion. The app has not yet been run against it on physical devices. Treat push delivery as unverified until the two-device checklist in `supabase/README.md` passes.

There are no purchases, custom audio, or production effect animations yet. The four effects are represented with SF Symbols, accent colours, and basic native motion. Do not claim a generated notification or “delivered” status.

Use native SwiftUI. Do not build a landing page, wrap a web app, or create Android infrastructure without a platform requirement. Evolve the included source rather than re-scaffolding repeatedly.

### Product
Tap a person. Send a small signal. They can reciprocate without composing a message. Preserve Yo’s simplicity while exploring expressive, recognizable effects.

Support close friends and couples without assigning relationship categories. The approved tone combines affection and playful mischief. Do not position a basic tap as novel by itself; similar apps exist. The quality of the exchange and whether people voluntarily return must carry the product.

### Production v1
- A compact home screen of accepted connections with large, tactile tap targets.
- Minimal identity and onboarding. Explain what happens before requesting notifications.
- Invite link and code flow, including pending, accepted, expired/revoked, and wrong-account cases. Mutual acceptance is required before messages can be sent.
- One free signal, Psst (thinking of you). A normal send is one tap.
- Real push notifications, actionable reciprocation where supported, and a usable in-app inbox/state when notification permission is denied.
- Distinguish sending, server acceptance, failure, and actual observed receipt. APNs acceptance is not proof of device delivery. Never animate a successful remote receipt without evidence.
- Handle offline operation, retry, idempotency, duplicate taps, stale device tokens, account/device changes, blocked users, and notification deep links.
- Block, remove connection, rate limiting, notification preferences, and quiet behavior. The design must not encourage harassment or relentless tapping.
- Small expressive visual/audio effects that remain compatible with platform rules. Remote push cannot promise arbitrary custom vibration, guaranteed timing, or bypassing Focus/silent settings. Verify current Apple capabilities before implementing.
- A bounded “same moment” reaction when both people actually reciprocate within a documented interval, if it improves the main interaction. Use server timestamps and test edge cases; defer it if it delays reliable delivery.
- Optional favorite-person widget only after the app-to-app loop is reliable. Establish widget limitations honestly.
- Account deletion, connection revocation, token cleanup, privacy/support, and purchase restoration.

Do not add a public feed, location tracking, strangers directory, group chat, or general messenger. Do not upload the address book by default; invite links/codes are sufficient to start.

### Backend
Use a small authenticated backend with a relational connection model, authorization at every endpoint, server-owned APNs credentials, deduplication keys, and rate limits. Pick one maintained stack after checking existing infrastructure; Supabase/Postgres with server functions is an option, not a mandate.

Connection checks, blocking, entitlements, and rate limits must be enforced server-side. Clients cannot send as another user or access another pair’s state. Separate development and production credentials. Keep tokens and credentials out of source control and logs. Design minimal retention and deletion before collecting data.

### Monetization hypothesis
Keep ordinary sending, receiving, and invitations free. Test permanent premium sound/visual collections; earlier ideas were roughly US $2.99–$4.99. Giftable collections can follow once entitlement transfer is explicitly designed. A subscription is deferred unless recurring value proves strong enough. Never gate basic reciprocity or charge both sides merely to communicate.

## Reliability and integrity
Implement a typed signal event with unique ID, sender, accepted connection, effect ID, and server timestamp. Enforce sender identity, mutual connection, block state, rate limits, and any effect entitlement at the server. Never trust a client-side success animation as proof of delivery. Verify current primary Apple documentation for APNs, notification actions, sound, and widget capabilities.

Previewing an effect must never send it. Retry must not duplicate it. Define queued/offline behavior explicitly. Keep sound optional and observe device settings; do not promise arbitrary remote haptics or bypass Focus/silent mode. Use server data for reciprocal-event timing, if that feature is retained.

## Purchases and measurement
Core sending, receiving, replying, and the four starter signals remain free. Add permanent themed effect collections only after the basic exchange is appealing. Free recipients can receive paid effects. Previously suggested US $2.99–$4.99 prices are hypotheses. Do not launch a subscription without recurring value.

Use StoreKit 2 with localized prices, verified entitlements, restoration, pending/cancelled/failed transactions, and refunds/revocation. Start with StoreKit configuration and sandbox validation. No real development purchases.

Measure accepted invites, first two-way exchanges, repeat voluntary exchanges, failures, notification opt-out, blocks, and actual purchase cohorts. Avoid contact/message content in analytics and disclose actual collection. Downloads alone are not evidence of a business.

## Execution
1. Refine the included local prototype: sender and recipient states, reciprocal action, and accessible/reduced-motion behavior. Label every simulated step honestly.
2. Deliver the real vertical slice: two accounts on two installations, mutual connection, authenticated send, actual push receipt, notification-open routing, and tap-back. Test on physical devices for push behavior that simulator testing cannot establish.
3. Complete recovery, offline/retry behavior, abuse controls, preferences, deletion, and effect design. Introduce one premium collection only after the free exchange works.
4. Verify StoreKit, accessibility, privacy, and release artifacts. Optional widgets and gift purchases follow later.

Keep tests focused on authorization boundaries, deduplication, connection/block state, stale token cleanup, deep links, permission denial, queue behavior, deletion, and purchase entitlements. Visually review compact and large phones, large text, VoiceOver, and Reduce Motion. Test empty/pending states and actual errors, not just the happy path.

Deliver source, reproducible local and backend setup, migrations, configuration examples without secrets, a concise test report, and draft App Store metadata/privacy information grounded in actual implementation. Prepare reviewable results before seeking approval for production credentials, paid services, or App Store submission. Do not publish or execute real transactions without explicit authorization.

Use a small maintainable stack, concise progress updates, and bounded milestones. No public feed, relationship questionnaire, photo-sharing product, location tracking, general chat, or speculative cross-app integration. Ask only about consequential unresolved choices; otherwise state a reasonable assumption briefly and proceed. Never call a simulation a finished networking feature.
