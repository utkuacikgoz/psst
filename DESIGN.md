# Psst — design implementation guide

Read `CLAUDE.md` first. This guide is self-contained for this repository. Exact measurements and colours are starting specifications, not separately approved owner decisions.

## 1. What “finished design” means

The first screen must feel intentionally composed on a real phone. A pile of attractive components is not sufficient. Prioritize, in order:

1. The primary interaction is obvious and works.
2. One visual subject dominates.
3. Its scale, placement, and motion feel right.
4. Supporting controls are consistent and readable.
5. Loading, error, permission, and purchase states receive the same care.

Do not equate detail, decoration, more features, or more words with quality. Do not describe your work as “AAA,” “premium,” or “polished” as evidence. Show the running result.

## 2. Shared implementation tokens

Use one centralized token definition in this app (`Psst/DesignTokens.swift`). Do not scatter unrelated numbers through views.

| Property | Starting specification |
|---|---|
| Spacing scale | 4, 8, 12, 16, 24, 32, 48 points |
| Main side inset | 24 points; 20 on very narrow phones |
| Touch target | At least 44 × 44 points, including icon-only controls |
| Primary action size | Use the app-specific layout below |
| Sheet inset | 24 points |
| Ordinary control radius | 0 points for primary colour bands; native sheets retain platform shape |
| Text | System SF family; no downloaded font dependency |
| Body / important labels | 17 / 15 points, scalable |
| Secondary metadata | 13 points minimum; never essential information in tiny text |
| Main text contrast | At least 4.5:1 against its actual background |
| Meaningful icon / control edge contrast | At least 3:1 where needed to identify the control |

Use semantic text styles or scaled metrics. Avoid forced truncation for key actions. At accessibility text sizes, reflow or scroll secondary content instead of shrinking text. Insets exclude safe areas; do not hard-code status bar or home indicator heights.

Use SF Symbols at one consistent weight for utility controls. Avoid mixing line icons, emoji, filled clip art, and multiple icon families. Give every icon-only action a VoiceOver label.

## 3. App-specific design

This app is about people and one-tap contact. Its tone is warm with optional mischief: an inside joke between people who care about each other. Keep the interface restrained and make the exchange expressive.

### Owner-selected reference: original Yo

The owner explicitly chose **Yo** after rejecting the earlier cobalt-card design. This supersedes the previous small-header/rounded-white-row direction.

- Use edge-to-edge, solid colour bands with large centered uppercase contact names.
- Purple canvas (`#713F93`); white type on strong blue, teal, orange, pink, and violet bands. Contact colour is stable for a name, not a network status.
- Header uses a bold 40-point “psst” wordmark. Contact names begin at 52 points and scale with Dynamic Type. Long names wrap instead of clipping.
- No rounded contact cards, perimeter gutters, outlines, persistent decorative symbols, or large explanatory paragraphs.
- The entire person band sends a Psst, the only signal. Nothing else lives inside the band. Removing or blocking a person is a separate action: Settings → People, a long press on the band, or the VoiceOver "Manage" action.
- A single connection gets a larger band; multiple connections become a scrollable stack. Never invent contacts to fill space.
- In the local demo, one concise notice identifies the fictional contact and local-only exchange. Do not repeat the full disclaimer in every control. Preserve honest statuses and VoiceOver hints.
- There is no signal picker: the owner reduced the app to one signal, Psst (25 Sep 2026).
- Recipient view uses the received signal’s colour, large signal name, sender identity, and a clear reply band.
- Press feedback is a brief local colour change. On success, the signal can briefly replace the contact name before the name returns. Do not imply remote delivery.
- Keep safe areas, Dynamic Type, reduced motion, readable contrast, and minimum touch targets. At accessibility sizes, allow the content to scroll and stack controls.

Reference: original Yo contact-band screenshots, https://www.macrumors.com/2014/06/20/yo-vulnerable-hacking/ . This is a visual reference; Psst keeps its own name, effects, and backend.

### Send feedback must be truthful

1. Touch: immediate local press response. This acknowledges the finger, not delivery.
2. Request pending: a restrained progress treatment confined to that row.
3. Backend accepted: show **Sent** briefly, if that is what the system knows.
4. Failed: visible **Not sent · Retry** near that person. Retrying cannot create duplicates.
5. Received/read: show only if the backend has that exact evidence. Never use a check mark whose meaning is ambiguous.

A playful burst must be brief and local to the interaction. No full-screen confetti on ordinary sends. The receiver’s presentation should identify the sender before showing an effect. Sound respects device/platform settings.

Pending invitations are visually different from sendable connections. A blocked connection cannot retain an active send target. Denied notifications and offline state need small, actionable explanations; do not display a generic error wall.

### Effects and purchases

Preview effects locally with a clearly labeled preview button. A preview must never accidentally message a person. State who can use a purchased effect and whether recipients need to buy anything. Ordinary sending/receiving stays free.

Separate effect selection from payment. No launch paywall, blurred essential controls, fake unread badge, subscription preselection, countdown, or hidden recurring terms.

## 4. Copy

- Say what an action does: **Invite**, **Retry**, **Restore purchases**.
- Do not put jokes into permission explanations, errors, prices, privacy, account deletion, or purchase results.
- Do not add a tagline to fill empty space.
- Avoid “Your journey,” “Unlock your potential,” “A little care. A little chaos,” “Your resident troublemaker,” or other decorative copy from the rejected version.
- Do not explain implementation details in the product UI.

## Visual acceptance checks

Use screenshots from the running native app, not a generated mockup. Inspect a compact iPhone and a large iPhone, ordinary and accessibility text sizes, sender/recipient states, and any purchase/permission/error screens implemented.

Check every item:

- [ ] The correct app and primary action are recognizable within a glance.
- [ ] Status bar, safe areas, and home indicator remain readable and unobstructed.
- [ ] Controls remain reachable; text does not collide, overlap, or silently disappear.
- [ ] Secondary screens have a visible or native, accessible exit.
- [ ] Pressed, disabled, loading, success, and error states look deliberate.
- [ ] VoiceOver labels match actions; colour and sound are never the only feedback.
- [ ] Repeated taps, interrupted animation, background/resume, and Reduce Motion behave sensibly.
- [ ] Delivery feedback matches real system state, including offline and permission-denied cases.
- [ ] Purchase previews are separate from sending/buying; prices come from StoreKit.
- [ ] There are no placeholder assets, fake friends, fake stats, decorative badges, or dead controls presented as finished features.
