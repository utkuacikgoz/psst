# Psst

Native SwiftUI iPhone app, iOS 17+, no third-party packages. Open `Psst.xcodeproj` in Xcode 16 or later and Run.

The app has two modes:

- **Local preview** (default, no setup): one fictional connection, Alex. Everything happens on this phone and is labelled that way.
- **Live**, when `Config/Secrets.xcconfig` points at a Supabase project: real accounts, invites, sending, push notifications and tap-back. See [`supabase/README.md`](supabase/README.md) for setup and the two-device checklist. The development backend is deployed and passes the live server checks (`scripts/smoke_live.py`); push delivery on physical devices is not yet verified.

## Start Claude Code here
Read `CLAUDE.md`, then `DESIGN.md`. This folder is an independent repository with no dependency on another project.

## Try the local preview
1. Tap **Alex** to play a Psst on this phone.
2. Tap **Alex’s side** to see the recipient side: first who it's from, then the effect.
3. Tap **You** on Alex's phone to tap back, then **Your phone** to return and see Alex's reply play on the row.

## What the states mean
| Row text | Meaning |
|---|---|
| Tap to psst | Nothing exchanged yet |
| Psst · played locally | You tapped. Alex's simulated screen hasn't been opened since then |
| Psst · seen in demo | Alex's simulated screen displayed it |
| Psst back from Alex | Alex tapped back most recently |
| A little breather. Try again shortly. | More than 5 taps in 20 seconds; resumes after 20 seconds |

Taps less than 0.8 s apart count as one. Each signal event has a unique ID, and retrying the same ID never creates a duplicate. These are the same rules the backend will have to enforce.

## Local preview limits
Every exchange is a local demonstration with a fictional Alex. No notifications are sent. There is no custom sound, network backend, account system, invitations (the **+** button says so), or StoreKit. Four SF Symbols and short keyframe motion stand in for the effects until production artwork exists. With Reduce Motion on, effects are a short fade. Haptics play locally on supported hardware. The word “local” in the interface is intentional.

Installing on a physical device requires your own signing team. No App Store release has been attempted.

## Build and test
```sh
xcodebuild test -project Psst.xcodeproj -scheme Psst \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PsstTests CODE_SIGNING_ALLOWED=NO
```
`.github/workflows/ios.yml` runs the unit tests on pushes to `main` and on pull requests that change the app. Screenshots run only when started by hand (Actions → iOS build and tests → Run workflow): four parallel shards (compact and large iPhone × standard and largest accessibility text), with JPEG review copies force-pushed as the single commit on the `screenshots` branch. Their artifacts expire after a day, and `.github/workflows/cleanup.yml` sweeps older artifacts and runs weekly. `.github/workflows/backend.yml` runs the database and edge-function tests.

- `PsstTests/LocalExchangeTests.swift`: the local preview rules (every tap is Psst, unique IDs, idempotent retry, tap coalescing, burst pause, receipt only after display, tap-back).
- `PsstTests/LiveStoreTests.swift`: live rules against a fake API (onboarding phases, sign-out, retry reusing the event ID, taps ignored while sending, rate-limit and ended-connection handling, acking only while visible, idempotent notification reply, account deletion), and parsing of Postgres timestamps, rows, errors, push payloads and invite links.
- `supabase/tests`, `supabase/functions/tests`: see the backend README.

## Layout
```
Psst/
  PsstApp.swift            picks live or local preview
  DesignTokens.swift       spacing, radius, touch size, colours (single source)
  Signal.swift             the one signal, Psst: copy, symbol, colour, motion, haptic
  PersonRow.swift          the large tap target
  SignalGlyph.swift        row-local effect, Reduce Motion aware
  ViewHelpers.swift        sheet chrome, pinned footer
  LocalExchange.swift, HomeView.swift, AlexPhoneView.swift, InviteUnavailableSheet.swift
                           local preview
  Live/
    AppConfig.swift        backend settings from Info.plist
    APIClient.swift        Supabase auth, RPCs, functions; Keychain session
    LiveStore.swift        send states, retry, unseen/ack, notifications, account
    AppDelegate.swift      push registration, notification actions and routing
    *View.swift, *Sheet.swift  onboarding, home, invite, connection, settings
Config/                    xcconfig, Info.plist, entitlements, Secrets.example.xcconfig
supabase/                  migrations, edge functions, backend tests
PsstTests/, PsstUITests/
```

## Visual direction
The owner-selected reference is the original Yo: edge-to-edge colour bands, oversized contact names, and direct tap feedback. Demo, recipient view, and live contact rows share the revised language. The app has one signal, Psst. Existing networking, authorization, notification, and exchange state logic is retained. See `DESIGN.md`.

Validation for the Yo-inspired revision: 34 existing unit tests passed, the final simulator build succeeded, and local send → effect selection → recipient → tap-back was checked in the running iPhone 17 Pro simulator. Physical-device push delivery and the deployed backend remain unverified.

## Website

`site/` holds the public pages served by Vercel at https://psstapp.fun: `/privacy`, `/terms` and `/support`, plus a small home page. Vercel needs no settings: the root `vercel.json` publishes `site/` as static files (leave Root Directory empty; `site/vercel.json` covers the case where it is set to `site`). The app links to these pages from Settings and from the Psst+ sheet.
