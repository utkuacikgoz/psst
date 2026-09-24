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
| Ordinary control radius | 12 points; circles only for deliberately circular actions |
| Text | System SF family; no downloaded font dependency |
| Body / important labels | 17 / 15 points, scalable |
| Secondary metadata | 13 points minimum; never essential information in tiny text |
| Main text contrast | At least 4.5:1 against its actual background |
| Meaningful icon / control edge contrast | At least 3:1 where needed to identify the control |

Use semantic text styles or scaled metrics. Avoid forced truncation for key actions. At accessibility text sizes, reflow or scroll secondary content instead of shrinking text. Insets exclude safe areas; do not hard-code status bar or home indicator heights.

Use SF Symbols at one consistent weight for utility controls. Avoid mixing line icons, emoji, filled clip art, and multiple icon families. Give every icon-only action a VoiceOver label.

## 3. App-specific design

This app is about people and one-tap contact. Its tone is warm with optional mischief: an inside joke between people who care about each other. Keep the interface restrained and make the exchange expressive.

### Starting palette and type

- Canvas: deep cobalt `#2448D8`.
- Main text: `#FFFFFF`.
- Raised person surface: `#FFFFFF`; text/icon: `#17224D`.
- Success/error feedback uses explicit wording and an icon, not colour alone.
- System SF Pro, regular/semibold. Avoid rounded toy typography here.

Validate actual contrast, including disabled and pressed states. Do not layer several translucent blue surfaces with indistinguishable boundaries.

### Home screen

```text
[safe area]
psst                                      [+]

[Ada                                    tap]
[Emre                                   tap]
[Sam                                    tap]

               empty space is allowed

[quiet access to settings / effects]
[safe area]
```

- Small wordmark/header, one explicit add-person action.
- A single column of large person rows. Start at about 88 points high, 12-point radius, 12-point separation. Names approximately 24-point semibold and readable at large text sizes.
- The whole row is the send target. Do not put secondary destructive controls inside it. Connection details/effect selection use a separate, clearly accessible action rather than an undiscoverable long press alone.
- With one connection, show one excellent row. Do not fill the screen with invented friends, sample activity, tips, cards, or prompts.
- With many connections, scroll the person list. No fake feed or analytics dashboard.
- Empty state: one plain sentence and **Invite someone**. No elaborate illustration or multi-step tour.

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
