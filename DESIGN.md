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
- The entire person band sends a Psst, the only signal. Nothing else lives inside the band. Remove, Block and Report are separate: a long press on the band (the iPhone context menu), Settings → People or the VoiceOver "Manage" action (the standard action sheet). Each asks for confirmation with a one-line explanation before anything happens. Report also blocks.
- Before anyone accepts, home is a single gold band: INVITE YOUR FIRST PERSON.
- A band's line appears only while something is happening (Sending…, Sent, Not sent · Retry). Settled outcomes sit small in the band's bottom-right corner: "sent", or "seen ✓" once their app actually showed it.
- After the server's pacing limit (10 a minute to one person), the band dims and reads "Try again in 0:42"; taps are ignored until then.
- Offline, notifications off and ended connections appear as a full-width dark strip under the wordmark, never as a pop-up.
- Home order: pinned people first (anyone you placed by holding and dragging a band onto another), then everyone else most recent first. The recency order refreshes only when home appears, never while you're tapping, so a band never moves under a finger. VoiceOver offers Move up / Move down. Settings → People can reset to most recent. The placed order stays on the phone.
- When several people pssted while you were away, each gets their own full-screen moment in turn (about 1.4 s each, newest last), labelled "1 of 3 · Tap to psst back". Tapping one pssts that person back and moves on.
- Problem lines are short, true and a bit playful: "Didn't make it · tap to try again", "Offline · taps won't get through", "Ada isn't here any more." Never blame the person, and never claim something was sent when it wasn't.
- Settings lists your open invites (unused, not cancelled, not expired) with their code, time left and Cancel. Home shows people only.
- After Delete account the app returns straight to the name screen.
- A newcomer who opens an invite link sees the inviter first: their colour, NAME / wants to psst you / First, what should Kim call you?, then name and notifications. The invite is accepted for them at the end and Kim's welcome plays. An unusable invite skips the intro and the invite sheet explains why.
- The local demo's Alex's side uses the real full-screen arrival, under a LOCAL DEMO · ALEX'S SIDE label.
- Invite links are web links: https://psstapp.fun/invite/CODE. With Psst installed they open the app (universal link, applinks:psstapp.fun). Without it they open a pink page on psstapp.fun with the code, a Copy button and the steps; the code still works after installing.
- Home-screen widget (Psst+): small shows your first person, medium your first three, as colour bands in home's order and your chosen colours. Tapping a band opens Psst and sends that person a Psst, with the same pacing and retry as at home. Without Psst+ the widget says "Psst+ puts your people here" and opens Psst+.
- Psst+ (optional one-time unlock): home's footer reads Settings · Psst+ (PP2). The Psst+ sheet is a standard list (PS1): what's included, the App Store's local price, Unlock, Restore purchase, and "Pssting, replies and invites are always free." Once unlocked, the same sheet holds the app icon and whisper sound choices. A band's long-press menu has Colour… (BC1): eight colours, on your phone only. Without Psst+, Colour… opens the Psst+ sheet.
- Accounts are anonymous and live on one phone. On a new phone you choose your name again and re-invite your people (owner decision NP1).
- The first time home has someone to tap, a one-time dark overlay shows a tapping hand: "Tap a band to psst" / "Hold to move someone or remove them". Any tap only dismisses it; it never sends.
- Typeface (owner pick, 25 Sep 2026): **Inter Tight**, the same face as psstapp.fun. It's bundled in the app (Psst/Fonts, SIL Open Font License) and used through `Font.psst(...)`: Black for band names and headlines, Bold/SemiBold/Medium for lines and labels. It scales with Dynamic Type. Standard iPhone lists (Settings, Psst+, alerts) keep the system font. SF Symbols stay on the system font.
- App icon (final, owner-approved 25 Sep 2026): the white lowercase "psst" wordmark on #713F93, matching the launch screen. Psst+ offers Night, Gold and Pink versions of the same mark.
- The notification's button reads "Psst back".
- Same moment: when both people psst each other within 10 seconds by the server's clock, both phones show your purple half above their colour with a white SAME MOMENT label, for about 2.5 seconds. At most one per pair per minute. Tapping closes it without sending.
- The shared invite reads: "I want to be able to psst you. Tap to join me (code K7QX4MPA)." plus the link. An invite link opens the I HAVE A CODE step with the code filled in.
- Notifications use a bundled whispered "psst" (`Psst/psst.wav`, about half a second, generated by `scripts/make_psst_sound.py`). iPhone's silent switch, Focus and per-app sound settings still decide whether it plays.
- When someone new becomes tappable (you accepted, or they accepted yours), their colour fills the screen once: NAME / IS IN / Tap to send your first Psst. People already connected on first launch, or who have already exchanged a Psst, get no welcome.
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
