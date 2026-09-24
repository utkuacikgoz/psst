# Psst — native interaction prototype

Open `Psst.xcodeproj` in Xcode 16 or later, choose an iPhone simulator, and Run. iOS 17+. No packages or API keys are needed.

## Start Claude Code here
Read `CLAUDE.md`, then `DESIGN.md`. This folder is an independent repository with no dependency on another project.

## Try it
1. Tap **Alex** to play the selected signal on this phone.
2. Tap **Signal for Alex · Change** to pick another signal. **Preview** plays it in the sheet without sending anything. The choice is remembered on this device.
3. Tap **View Alex's phone (simulated)** to see the recipient side: first who it's from, then the effect.
4. Tap **You** on Alex's phone to tap back, then **Your phone** to return and see Alex's reply play on the row.

VoiceOver users can also use the **Choose signal** action on the Alex row.

## What the states mean
| Row text | Meaning |
|---|---|
| Tap to play Psst | Nothing exchanged yet |
| Squeeze · played on this phone only | You tapped. Alex's simulated screen hasn't been opened since then |
| Squeeze · shown on Alex's simulated phone | Alex's simulated screen displayed it |
| Alex sent Oi back | Alex tapped back most recently |
| Paused for a moment after several taps | More than 5 taps in 20 seconds; resumes after 20 seconds |

Taps less than 0.8 s apart count as one. Each signal event has a unique ID, and retrying the same ID never creates a duplicate. These are the same rules the backend will have to enforce.

## Limits
Every exchange is a local demonstration with a fictional Alex. No notifications are sent. There is no custom sound, network backend, account system, invitations (the **+** button says so), or StoreKit. Four SF Symbols and short keyframe motion stand in for the effects until production artwork exists. With Reduce Motion on, effects are a short fade. Haptics play locally on supported hardware. The word “local” in the interface is intentional.

Installing on a physical device requires your own signing team. No App Store release has been attempted.

## Build and test
```sh
xcodebuild test -project Psst.xcodeproj -scheme Psst \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
`.github/workflows/ios.yml` runs the same command on a GitHub macOS runner for every push.

`PsstTests/LocalExchangeTests.swift` covers: choosing never sends, the favorite persists, unique IDs, idempotent retry, repeat-tap coalescing, burst pause and resume, pausing only the sender, receipt claimed only after the other screen displayed the signal, tap-back mirroring, and bounded history.

## Layout
```
Psst/
  PsstApp.swift            app entry
  DesignTokens.swift       spacing, radius, touch size, colours (single source)
  Signal.swift             the four signals: copy, symbol, accent, motion, haptic
  LocalExchange.swift      on-device exchange model (events, idempotency, pacing, status)
  HomeView.swift           your phone
  PersonRow.swift          the large tap target
  SignalGlyph.swift        row-local effect, Reduce Motion aware
  SignalPickerSheet.swift  choose and preview, never sends
  AlexPhoneView.swift      simulated recipient and tap back
  InviteUnavailableSheet.swift
PsstTests/
  LocalExchangeTests.swift
```
