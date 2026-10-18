# Psst — design implementation guide

Read `PROJECT.md` first. This guide is self-contained for this repository. Exact measurements and colours are starting specifications, not separately approved owner decisions.

## October 2026 approved feature direction

The latest owner decisions supersede earlier restrictions on persistent row
metadata and personal-only Psst+ extras. See `docs/FEATURE_RELEASE.md` for the
complete behavior: latest exchange time, private activity rankings,
Super Psst in each person’s long-press menu (one daily total; unlimited with verified Psst+),
optional recipient effects, one-time feature introduction and a subtle vector cat.
Ordinary taps and replies remain free Pssts. Purple wordmark stays the default
icon; Mischief is an optional icon. Functional titles use system tracking and
wrap without shrinking away accessibility text sizes.

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

This app is about people and quick contact. Its tone is warm with optional mischief: an inside joke between people who care about each other. Keep the interface restrained and make the exchange expressive.

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
- Settings › People lists your open invites (unused, not cancelled, not expired) with their code, time left and Cancel. Home shows people only.
- Your name (owner picks NM1 + ED1, 6 Oct 2026): first launch asks "What do your people call you?" with one line on what the name is for, then you type into your own band; below it, "Only your people see it. Change it anytime in Settings." (copy tightened in the 12 Oct design review) Settings opens with your band (YOU / your name, in your colour) and an Edit name button that opens the same band editor, filled in. The name is kept on this phone once saved; installs from before that show "Add your name" until it is saved once.
- After Delete account the app returns straight to the name screen.
- A newcomer who opens an invite link sees the inviter first: their colour, NAME / wants to psst you / First, what should Kim call you?, then name and notifications. The invite is accepted for them at the end and Kim's welcome plays. An unusable invite skips the intro and the invite sheet explains why.
- The local demo's Alex's side uses the real full-screen arrival, under a LOCAL DEMO · ALEX'S SIDE label.
- Invite links are web links: https://psstapp.fun/invite/CODE. With Psst installed they open the app (universal link, applinks:psstapp.fun). Without it they open a pink page on psstapp.fun with the code, a Copy button and the steps; the code still works after installing.
- Lock Screen widget (Psst+, owner go 10 Oct 2026): your first person as their initials (circular) or name (rectangular); one tap sends them a Psst; without Psst+ it opens Psst+.
- Home-screen widget (Psst+; back in builds from 10 Oct 2026 once the widget App ID exists): small shows your first person, medium your first three, as colour bands in home's order and your chosen colours. Tapping a band opens Psst and sends that person a Psst, with the same pacing and retry as at home. Without Psst+ the widget says "Psst+ puts your people here" and opens Psst+.
- Rating: after your first Psst the server accepts (never a failed one), once its "sent" has shown and nothing else is on screen, Psst asks Apple to show its rating prompt, once per install. Apple decides whether it appears (at most three times a year); screenshot runs never ask.
- Psst+ (optional one-time unlock): home's footer reads Settings · Psst+ (PP2). The Psst+ sheet is a standard list (PS1): what's included, the App Store's local price, Unlock, Restore purchase, and "Pssting, replies and invites are always free." Once unlocked, the same sheet holds the app icon and whisper sound choices (Whisper, Soft, Quick, and since 10 Oct 2026 Double, Low and Long; the server allow-list must include a sound before the app offers it). A band's long-press menu has Colour… (BC1): twelve colours (four added 10 Oct 2026), on your phone only. Without Psst+, Colour… opens the Psst+ sheet.
- Accounts are anonymous and live on one phone. On a new phone you choose your name again and re-invite your people (owner decision NP1).
- The first time home has someone to tap, a one-time dark overlay shows a tapping hand: "Tap a band to psst" / "Hold for Super Psst". Any tap only dismisses it; it never sends.
- Design review (owner go, 12 Oct 2026): names and headlines are Inter Tight Black everywhere (no SF in brand moments); the + band is a fixed 96 pt strip so people get the height; one gold (#A66700); each person's usual colour is given in join order (keeping their old name colour when free) and home never shows two neighbours in the same usual colour; arrivals show FROM / NAME / "psst" with a PSST BACK band at the bottom; same moment uses full-size names with the halves meeting at the seam; the Super Psst sheet is the person's band; What's new shows only to people who had Psst before and have someone to psst.
- Leaderboard and band line (owner picks, 12 Oct 2026): Your Psst activity is a podium (top three as bands in their colours with the count, everyone else in a list), switchable Sent to / Received from / Both, counted over all time (This month removed, owner, 13 Oct 2026); all time comes from two counts per pair kept beyond the 30-day purge. A band's exchange line reads "Sent 1m ago · seen ✓" (just "Sent 1m ago" until they open it), with no separate corner word.
- Super Psst button (owner pick, 12 Oct 2026): a small ✦ in each band's bottom-right corner (44 pt target) opens the Super Psst sheet; tapping the band still sends a Psst, and holding still works.
- The Psst is the invite (owner pick 5A, 14 Oct 2026): the invite sheet's top band is PSST SOMEONE NEW (pink, NEW tag, "Not on Psst yet? Your Psst is the invite."), above Share my invite and I have a code. It opens the share sheet with "I pssted you. Open it to see, and psst me back." and a one-person, seven-day link, psstapp.fun/p/CODE. That page reads "Utku pssted you." (first name only, noindex), a sealed "1 Psst from Utku · Waiting for you in the app", Get Psst to open it (copies the code), Open in Psst, and "This link is for one person · expires Oct 21". Joining delivers that Psst as their first: FROM UTKU · psst · "Sent yesterday, before you had Psst". The inviter's push: "Kim is in · Kim got your Psst and joined. Tap to psst them." Settings › Open invites shows it as "Psst waiting" with Cancel. Home still shows people only.
- Weekly recap (owner pick 4A, 14 Oct 2026; on from the start since owner pick 2A, 16 Oct 2026, for new and existing accounts, and the home opt-in strip is gone): Settings › Weekly recap turns it off. Sundays at 6 PM on your phone's clock, Monday to Sunday, weeks with no Pssts skipped. Push: "Your week: 38 Pssts" / "Kim is still your #1. You and Ada are on a 6-day streak." Opening it shows a full-screen recap on the canvas: YOUR WEEK and the dates, a gold band with the total and sent · received, your #1 in their colour ("YOUR #1 · STILL" when unchanged), your longest live streak in that person's colour, and a white PSST NAME band. No share button (topic 5 is being redone).
- Streaks (owner pick 3A, 14 Oct 2026; an approved exception to "nothing else lives inside the band"): a day counts when you and they have each pssted the other that day, each by your own phone's calendar. From 3 days, a flame and the number sit in the band's bottom-left corner, mirroring the nudge mark. When it grows, the number bumps and "7 days in a row" shows under the line for 3 seconds. It's alive while the last shared day is today or yesterday; missing a day starts again. No streak notifications by default.
- Doodles (owner picks 1A 2A 3B 4A 5A, 15 Oct 2026): hold a band → "Doodle for Mia" opens a full-screen pad in their colour: draw with one finger in white, Undo, SEND DOODLE (60 strokes / 2,000 points max). It arrives as a notification ("Mia · drew you something ✎") and a full-screen moment with the doodle as a tilted cream polaroid, "from Mia", and PSST BACK. It also shows on their Home Screen widget as that polaroid, free with or without Psst+, until they psst you back; while the app is closed the widget checks every 30 minutes. Stored with the Psst and deleted after 30 days like every Psst.
- Psst from Control Center (owner pick 2A, 15 Oct 2026; iOS 18+): a "Psst someone" control for Control Center, the Lock Screen or the Action button. It shows the cat and "Psst Mia" and sends a Psst to that person without opening the app; long-press to choose who (default: the top of home). Free, like pssting. Also a "Send a Psst" Shortcuts action.
- Group code filling up (owner pick 1C, 15 Oct 2026): home stays as it is. In the + sheet, once someone has joined your open code, Share my invite reads "3 of 10 joined · 6 days left" and opens that same code (not a new one) with ten dots filling as people join, the count and days left, who joined (only people still connected to you), and "Share again".
- Cat moods (owner picks 1A 2A 3A 4B, 14 Oct 2026, from Fevzi's ideas; the same white cat): a small sleeping cat under the version in Settings that opens one eye when tapped; home's "Loading your people…" shows the cat peeking over a line with its paws on it, looking left and right, instead of the spinner; where Psst can't connect (home, activity, weekly recap) a sad cat with ears down and a tear sits above the message and Try again; when a Psst arrives, a startled cat (ears up, wide eyes) peeks in from the right edge. Reduce Motion: no looking around, no slide-in.
- Home with few people (owner pick, 14 Oct 2026, commit 0b8d7da): bands fill the measured scroll area exactly, the scroll bar hides when everyone fits, the gap above Settings moved into the footer, and notices sit on the canvas colour; pull-to-refresh opens onto the first band's colour.
- Launch fixes (owner picks 1B 2B 3B 4A 5A 6A, 16 Oct 2026): a doodle's full-screen moment has ••• top left opening a small dark menu with Hide doodle (off your widget without pssting back, until a newer one comes), Block <name> and Report <name> (both red, same confirm as holding the band); the moment doesn't close on its own while that menu is open. When SEND DOODLE can't send yet, the button shakes with an error buzz (no shake with Reduce Motion) and the drawing stays. On light pages (Settings, the leaderboard) the white cat has a grey face and a thin grey edge. The recap says "1 PSST" / "1 Psst this week". The terms forbid objectionable doodles and promise reports are reviewed within 24 hours.
- Settings (owner pick 1B, 16 Oct 2026): a short front page like Apple's Settings. Your band; Your Psst activity › and Weekly recap › (On/Off); People › (count: your people, Sort by most recent, open invites, blocked), Notifications › (notification settings, haptics, Super Psst effects) and Psst+ › (Unlocked when bought; opens the Psst+ sheet) with the footer "People holds your people, open invites and blocked. Notifications holds haptics and Super Psst effects."; Privacy and help › (the links, the data paragraph as its footer); Delete account; the version and the cat.
- Super Psst as a small card (owner pick 1B, 16 Oct 2026): the Super Psst sheet is no longer a full page. A short card in their colour rises over home (home dimmed behind, grabber, rounded top), as tall as its state needs: the cat, SUPER PSST for NAME, the status line and a rounded white button inset from the edges. Every Direction A state (available, unlimited, loading, used for today with the Psst+ block, couldn't confirm, offline, sending, sent, didn't make it, paused, earlier Psst stuck, gone) shows in the card, which grows for the taller ones; drag down or tap outside to close.
- Doodle tip (owner pick 1B, 16 Oct 2026): once, over home, in the same dark overlay as the first tip: a pulsing scribble, "Hold a band to doodle", "Draw them something for their widget.", "Tap anywhere to start". Any tap dismisses it and nothing is sent. It never shows on the same launch as the first tip, nor over a sheet or an arrival.
- Your word (owner picks 1A 2A 3A, 16 Oct 2026; Psst+, 1.0.7): the Psst+ sheet has a "Your word" section under Whisper sound: eight chips, English only since 17 Oct 2026 (psst, hey, boop, oi, yo, hiii, mwah, psst psst), the chosen one filled in canvas purple, footer "What your people see when you psst them. Pssting is still free; your word is a Psst+ extra." One word for everyone you psst. Their notification reads "Mia · boop" and the arrival shows "boop" where "psst" was; Super Psst, doodles, home, widgets, invites and PSST BACK keep "psst". Fixed list, checked by the server; only shown while the sender's Psst+ is valid.
- Psst+ leads with your word (owner picks 1A 2A 3A, 18 Oct 2026; replaces PS1's opening): under the Psst+ title, a canvas-purple card: SAY IT YOUR WAY (before buying) or YOUR WORD (after), the word huge, "Pick the word your people see when you psst them." / "Your people see this when you psst them.", a white notification preview (your name · the word) and the eight word chips (white when chosen; before buying they only preview). Before buying: Unlimited Super Pssts, Your whisper sound, Home Screen and Lock Screen widgets, then the line "Also: band colours and app icons", then Unlock and Restore as before; the colour and icon preview grid is gone. After buying: the card, Whisper sound, then Looks (App icon › with the current icon, and "Band colours: hold someone's band → Colour…"). One-line pitch elsewhere (Super Psst card, site): "Your word, unlimited Super Pssts, whisper sounds and widgets."
- Audit picks (owner picks 1A 2A 3A 4A 5A 6A 7A 8A, 18 Oct 2026; 1.0.7): the name step has "Someone sent you a Psst?" with Apple's Paste button (dark capsule; a secure control needs contrast) that takes a pasted link, message or code and starts the invited intro. With nobody yet, home's gold band reads PSST SOMEONE NEW / "Your Psst is the invite." and goes straight to sharing a Psst link; holding it offers Share my invite. After a Psst link is made, the invite sheet shows "Your Psst is waiting for them · expires Oct 23"; if nobody opens it by day 5 the sender gets one push, "Your Psst hasn't been opened" / "Send it again?", that opens the share sheet with the same link. Link previews for /p/ and /invite/ show the inviter's first name ("Utku pssted you · 1 Psst waiting", "Utku invited you to Psst") with a #C2185B card. Copy: one offline message ("You're offline. Try again once you're back online."), "Couldn't … Try again." errors, "This invite has no places left. Ask for a new one.", "Tap the cat on a band for Super Psst", "Pssts still wait for you in the app.", the report confirm promises a review within 24 hours, the leaderboard footer is "Only you see this. Super Pssts count too.", the privacy line names doodles, the running counts and settings, the widget gallery says "the person at the top of Psst". Visual: the first tip uses Inter Tight on 0.8 black like the doodle tip; home's load error uses the psst font and "Try again"; at accessibility sizes the seen mark stays inline (no separate strip); arrival names and SAME MOMENT wrap instead of shrinking; the doodle ••• menu is 220–320 pt wide; Settings and Psst+ are fully light sheets; the Psst+ perk icon uses the one gold. The Control Center button asks for Face ID on a locked phone, and only the widget's own links (with this install's token) send a Psst.
- Doodle as the invite (owner picks 1A 2A 3A 4A, 18 Oct 2026; 1.0.7): in the + sheet, a DRAW SOMEONE NEW band (#C2185B, NEW tag, "Draw them something ✎ They see it when they join.") under PSST SOMEONE NEW opens the doodle pad in the link pink (#AC3E68), titled "For someone new", with SEND AS A LINK; the share sheet says "I drew you something. Open it to see, and psst me back." and the sheet then reads "Your doodle is waiting for them · expires …". The link page (psstapp.fun/p/CODE) reads "Utku drew you something.", shows a sealed cream polaroid (frosted pink, white SEALED ✎ sticker, "from Utku"; no strokes ever leave the server before joining), "1 doodle from Utku · Waiting for you in the app" and GET PSST TO SEE IT. Its link preview is its own card: "Utku drew you something" with the sealed polaroid tilted on #C2185B. Joining shows the drawing as their first moment (FROM UTKU, the polaroid, "Drawn yesterday, before you had Psst", PSST BACK); Utku's push reads "Kim is in · Kim got your doodle and joined. Tap to psst them."
- Cats in the pull gaps (owner pick 2A, 14 Oct 2026): pulling home down opens the gap in the first band's colour with the happy cat waving a paw, "I'm here!", instead of a spinner; pulling far enough (90 pt) refreshes, once per pull. Pushing up past the end opens a gold gap under the + band where the cat waves "Psst!". The gap above Settings now sits in the footer so the list ends flush. Reduce Motion: the cat doesn't wave.
- Super Psst nudge (owner pick 1A + shake, 14 Oct 2026): the ✦ is replaced by the nudge mark, the cat between two pairs of shake arcs, eyes in the band's colour (same corner, same target). Sending a Super Psst shakes the band's name side to side and pops the mark; a Super Psst arriving shakes the whole moment like the old MSN nudge. Reduce Motion: no shake (ripple flash and the cat's pulse only).
- 1.0.4 picks (owner, 13 Oct 2026): the version at the bottom of Settings, long-press to copy (since 14 Oct 2026 the app version only, "Psst 1.0.5", no build number: owner request); pull-down search on home once you have 5+ people (filters bands live); while a Psst sends, a light sweeps across the name (Reduce Motion: a gentle fade) instead of the small spinner; the invite page's main button is "Get Psst" (App Store, copies the code on the same tap) with Apple's Smart App Banner, and "Open in Psst" is a small link.
- Leaderboard robustness (owner go, 13 Oct 2026): it opens from the last result (kept on this phone, forgotten with the account) and refreshes quietly; Loading and "Couldn't load activity. Try again" only show when there's nothing to show. Equal counts share a rank (1, 2, 2, 4). Since owner pick 1B (18 Oct 2026) the three podium bands are one size (same height and name size), the ranks sit in one column so every name starts on the same line, and long names wrap to the left.
- Super Psst sheet, Direction A (owner pick, 13 Oct 2026): same composition (cat, SUPER PSST, for NAME, "Double whisper.", one white band); each state changes only the status line and what the band does. Used for today shows "Next free one at 3:00 AM · in 6 h 12 m" (plain text, no timer), a shaded Psst+ block, UNLOCK PSST+ · price (Apple's purchase sheet), Restore purchase and "Send NAME a Psst". Couldn't confirm Psst+ is a panel with Try again and Restore, and the free one stays sendable. The sheet waits for the server: SENDING… with the sweep, then SENT with the Ps-st pulse and closes; failures read "Didn't make it" with Try again (same event, no second free one). Offline, pacing ("A little breather", TRY AGAIN IN 0:42), an earlier Psst stuck (RETRY THAT PSST) and "NAME isn't here any more" each have their own state.
- Reusable invites (owner pick, 13 Oct 2026): a code joins up to 10 people within its 7 days. Share my invite reads "Send a link to your friends"; the code step reads "Works for up to 10 people · expires Oct 20" ("Works once" for older single-use codes). Cancelling a code stops further joins; people who joined stay.
- Sent effect (owner pick, 13 Oct 2026, "Ps-st"): when a Psst goes out or comes in, two strong pulses cross the band (a ring, then a ring with a flash, about a third of a second apart) and the name bumps with each; Reduce Motion shows one soft flash. Replaces the chat-bubble glyph.
- Updates (owner picks, 13 Oct 2026): below the server's minimum build, a full purple page "Time for a quick update" with one white UPDATE PSST band (App Store) and nothing else; when a newer version is out, the home notice strip "A new Psst is ready · Update ×", once per version. If the check can't reach the server, nothing is blocked.
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

### Latest discovery direction

The owner selected long press for now. Ordinary band taps send Psst immediately.
Touch and hold a person, then choose Super Psst to open the approved review;
Send Super Psst remains explicit. VoiceOver exposes the same action. Home has
no header action, repeated Super buttons or person-choice sheet. The introduction
and first-use hint explain the gesture. This supersedes the rejected placement
proposals and restores the original one-tap home behavior.

### Recovery states — owner-approved 13 Oct 2026

Home shows a load error with Try again when no people could be fetched, or a
Retry notice alongside cached people when refreshing fails. Settings keeps
known rows and shows loading or retry states for blocked people and open
invites; a failed request never becomes “No one.” The owner approved these
native previews while excluding the proposed Psst+ verification recovery UI.
Existing layouts and purchase verification remain in place.
