# App Review: notes and routine

**Owner decision (25 Sep 2026): option A.** The reviewer gets an invite code from a real account on the owner's phone, and the owner pssts back while the app is in review. No demo account or fake contact is built into the app.

## Before each submission

1. Install the **production** TestFlight build on your own iPhone. Start it with a clear display name, e.g. **Psst Team**.
2. On home, tap the gold **+** band → **Share my invite**. Write down the code, then do it once more for a second code, in case two reviewers try.
   - Since 1.0.4 each code lets up to **10** people join, within **7 days**. Make fresh ones for every submission.
   - Settings → Open invites shows which codes are still unused.
3. Paste the notes below into App Store Connect → the version → **App Review Information → Notes**, with your two codes filled in.
4. **Sign-in required:** No. There's no login; the account is created anonymously.
5. Contact information: your name, phone and email, so Apple can reach you if something's unclear.

## Memorable codes (used for the 1.0 submission)

The 1.0 submission used `PSSTTEAM` and `PSSTBACK`. They were created for the **Psst Team** profile in the production SQL editor, valid for 30 days:

```sql
insert into public.invites (code, inviter_id, expires_at)
select v.code, p.id, now() + interval '30 days'
from public.profiles p, (values ('PSSTTEAM'), ('PSSTBACK')) as v(code)
where p.display_name = 'Psst Team';
```

For a later submission, pick two new unused codes. Codes inserted this way take the table default: up to 10 joins since 1.0.4 (codes made before that work once).

## While in review

- Keep your phone's notifications **on** for Psst. When the reviewer's Psst arrives, psst back within a few minutes. Try once to psst back within 10 seconds, so they can see SAME MOMENT.
- In the Supabase dashboard, a new connection appears in `public.connections` the moment a code is used. You can also just watch your phone's home screen for a new band.
- After approval, remove the reviewer's band if you like: hold the band → Remove.

## Notes to paste (fill in the two codes)

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap the gold + band → "I have a code" and enter:  CODE-1
   (backup code, if the first was already used:  CODE-2)
3. Tap "Connect with Psst Team". A band for "Psst Team" appears on home.
4. Tap that band to send a Psst. We'll psst you back within a few minutes during review hours, and you'll see the full-screen arrival. If both of you psst within 10 seconds, both phones show SAME MOMENT.
5. Long-press a notification to use "Psst back" without opening the app.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. Reports are reviewed by the developer. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable): home → "Psst+" next to Settings → Unlock. Once unlocked, the same sheet offers alternate app icons and whisper sounds, and holding a band → "Colour…" picks that person's colour. "Restore purchase" is on the same sheet. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

## If Apple asks for "Information Needed" (Guideline 2.1)

Apple asked this for build 7. They want a **screen recording from a physical iPhone** on the latest iOS. Record it yourself with Control Centre → Screen Recording, on a fresh install of the TestFlight or review build. Keep it under about 3 minutes:

Recording alone? In the app, tap + → Share my invite and note the code. Then run Actions → **Stand-in friend** with that code. A temporary "Zoe" joins, sends you one Psst after 30 seconds, pssts back when you psst her, and deletes her account after 10 minutes. The first time, connect with the code instead of step 2 below.

1. Delete Psst, reinstall, and open it. Enter a name, read the notification explainer, then Allow.
2. Tap the gold + band, then "I have a code". Enter an unused code and connect. The band appears.
3. Tap the band to send a Psst. Show one arriving from the other phone and tap Psst back. Long-press a notification to show "Psst back".
4. Hold a band to show Remove, Block and Report. Cancel.
5. Open Psst+ (next to Settings) and show the price, Unlock (sandbox), Restore, and Terms and Privacy. If you're signed into the sandbox, unlock it and show the icon, sound and Colour… choices.
6. Open Settings to show Delete account and its confirmation. Cancel unless you're using a throwaway account.

Attach the video in App Store Connect under App Review Information → Attachment, then reply with:

```
1. Purpose: Psst lets two people who have both agreed to connect send each other a one-tap "Psst" (thinking of you), and psst back in one tap. Audience: friends, family and couples. It has no feed, no chat, no strangers and no location.
2. Setup: no login. An anonymous account is created when you enter a name. To connect with our team, use invite code PSSTTEAM (backup: PSSTBACK) via the gold + band → "I have a code". We psst back during review.
3. External services: Supabase (database, anonymous auth, server functions), Apple Push Notification service, and StoreKit for the Psst+ purchase. The privacy, terms and support pages are hosted on Vercel at psstapp.fun. No AI, ads, tracking or analytics SDKs.
4. Regional differences: none. The app is the same in every region.
5. Regulated industry: no. Fonts: Inter Tight, under the SIL Open Font License.
6. In-app purchase: Psst+ ("psstplus.unlock"), a non-consumable one-time unlock for personal extras: each person's band colour, alternate app icons and whisper sounds. Home → "Psst+" next to Settings. Restore is on the same sheet. Sending, replying and invites are always free.
7. Safety: hold any band to Remove, Block or Report (reporting also blocks). Settings → Delete account deletes all server data immediately.
```

Before sending, check that both codes are still unused (`select code, accepted_by from public.invites where code in ('PSSTTEAM','PSSTBACK');`). Build 7 still lists "Home-screen widget" in the Psst+ perks, so don't mention the widget in the reply.

## 1.0.1 (build 16)

Create two fresh codes for the Psst Team profile first (the 1.0 ones may be used up):

```sql
insert into public.invites (code, inviter_id, expires_at)
select v.code, p.id, now() + interval '30 days'
from public.profiles p, (values ('PSSTHEY2'), ('PSSTYAY3')) as v(code)
where p.display_name = 'Psst Team';
```

What's New in This Version:

```
Choosing your name is clearer, and you can now see and change it at the top of Settings. Invite links open Psst directly. Plus small polish and fixes.
```

Notes for the reviewer:

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

What's new in 1.0.1:
- First launch now asks "What do your people call you?" and explains that only people you connect with see the name.
- Settings opens with your name (your colour band) and an "Edit name" button.
- After your first Psst is accepted, the app may ask Apple to show the standard rating prompt (SKStoreReviewController / requestReview). It is asked once per install; Apple decides whether it appears.
- Invite links (https://psstapp.fun/invite/CODE) open the app directly.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap the gold + band → "I have a code" and enter:  PSSTHEY2
   (backup code, if the first was already used:  PSSTYAY3)
3. Tap Connect. A band for "Psst Team" appears on home.
4. Tap that band to send a Psst. We'll psst you back within a few minutes during review hours. If both of you psst within 10 seconds, both phones show SAME MOMENT.
5. Long-press a notification to use "Psst back" without opening the app.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable, unchanged): home → "Psst+" next to Settings → Unlock. It adds alternate app icons, whisper sounds and per-person band colours. "Restore purchase" is on the same sheet. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

---

## 1.0.3

Submit build **1.0.3 (22)**. The backend runs with Production purchases and also accepts Sandbox ones (TestFlight and App Review buy in Sandbox), so no switch is needed around review.

Before submitting, create two fresh review codes for the Psst Team profile:

```sql
insert into public.invites (code, inviter_id, expires_at)
select v.code, p.id, now() + interval '30 days'
from public.profiles p, (values ('PSSTWAVE'), ('PSSTHERE')) as v(code)
where p.display_name = 'Psst Team';
```

What's New in This Version:

```
Super Psst: tap ✦ on someone's band (or hold it) for a bigger, cheekier Psst. One free every day, unlimited with Psst+.
Your leaderboard: who you psst most and who pssts you, all time or this month. Only you can see it.
Get a notification when someone accepts your invite, and join with "I have a code" and Paste.
Plus a new "ps-st" vibration, a bolder look, clearer sent and seen, and fewer false "Offline" warnings.
```

Notes for the reviewer:

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

What's new in 1.0.3:
- Super Psst: tap the ✦ in the corner of a band (or hold the band) to open the Super Psst sheet, then "Send Super Psst". Everyone gets one free Super Psst per day; Psst+ makes them unlimited. Recipients can turn Super effects off in Settings.
- Settings → Your Psst activity: a private leaderboard (all time / this month). Only the account owner sees it.
- The person who shared an invite gets a notification when it's accepted.
- Home shows "I have a code" when you have no one yet; code entry has a Paste button.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap "I have a code" and enter:  PSSTWAVE
   (backup code, if the first was already used:  PSSTHERE)
3. Tap Connect. A band for "Psst Team" appears on home.
4. Tap the band to send a Psst; tap ✦ for a Super Psst. We'll psst you back within a few minutes during review hours. If both of you psst within 10 seconds, both phones show SAME MOMENT.
5. Long-press a notification to use "Psst back" without opening the app.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable): home → "Psst+" next to Settings → Unlock. It adds unlimited Super Psst, per-person band colours, alternate app icons, whisper sounds and Home Screen / Lock Screen widgets. "Restore purchase" is on the same sheet. The purchase is verified with Apple's App Store Server API. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

Psst+ in-app purchase description, max 55 characters (App Store Connect → In-App Purchases → psstplus.unlock → localization):

```
Unlimited Super Psst, colours, icons, sounds, widgets
```

App Privacy (App Store Connect → App Privacy), add to what's already declared:
- Purchases → Purchase History: App Functionality, linked to the user, not used for tracking (purchase verification record).
- Usage Data → Product Interaction: App Functionality, linked to the user, not used for tracking (daily Super Psst allowance; the leaderboard's two counts per connection).

## 1.0.4

Submit the TestFlight build that carries everything below (fill in the build number once it's uploaded). Like 1.0.3, the backend accepts both Production and Sandbox purchases, so there's no switch to make around review.

**Before submitting:**
1. Create two fresh review codes for the Psst Team profile. Each now lets up to 10 people join, so one code is enough even if two reviewers try; the second is a backup.

   ```sql
   insert into public.invites (code, inviter_id, expires_at)
   select v.code, p.id, now() + interval '30 days'
   from public.profiles p, (values ('PSSTJOIN'), ('PSSTNOW1')) as v(code)
   where p.display_name = 'Psst Team';
   ```

2. Check the forced-update settings are off. The submitted build must not be below `min_build`:

   ```sql
   select min_build, latest_build, latest_version from public.app_config;
   ```

   After approval and release, set `latest_build` / `latest_version` to the new build, which shows "A new Psst is ready" to people on older builds (docs/METRICS.md).

**What's New in This Version:**

```
• One invite code now works for up to 10 friends — drop it in your group chat
• Search your people: pull down on home
• A new sent effect, and a clearer Super Psst screen
• Your all-time Psst leaderboard
• Psst+ purchases now always unlock unlimited Super Pssts
• Faster, steadier, and fewer false "offline" messages
```

**Notes for the reviewer:**

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

What's new in 1.0.4:
- An invite code can now be used by up to 10 people within 7 days (each person who joins gets their own private, two-way connection with the inviter; nobody else sees it). The inviter can cancel a code in Settings → Open invites.
- Pull down on home to search your people (appears once you have 5 or more).
- The Super Psst sheet now shows each state clearly. When today's free Super Psst is used, it offers Psst+ (one-time purchase) with its App Store price, plus "Restore purchase" and a free normal Psst.
- Settings shows the app version. The app reports its version to our server so we can tell people when an update is available.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap "I have a code" and enter:  PSSTJOIN
   (backup code:  PSSTNOW1)
3. Tap Connect. A band for "Psst Team" appears on home.
4. Tap the band to send a Psst; tap ✦ for a Super Psst. We'll psst you back within a few minutes during review hours. If both of you psst within 10 seconds, both phones show SAME MOMENT.
5. Long-press a notification to use "Psst back" without opening the app.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable): home → "Psst+" next to Settings → Unlock, or from the Super Psst sheet once today's free one is used ("Unlock Psst+"). It adds unlimited Super Psst, per-person band colours, alternate app icons, whisper sounds and Home Screen / Lock Screen widgets. "Restore purchase" is on both sheets. The purchase is verified with Apple's App Store Server API. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

**App Privacy** (App Store Connect → App Privacy). Add this to what's already declared:
- **Diagnostics → Other Diagnostic Data:** App Functionality, linked to the user, not used for tracking. This is the app version and build saved on the account, used to offer and require updates.

The other 1.0.4 changes collect nothing new:
- Invites joined per code are already covered by the existing account and contacts-free connection data.
- Purchase verification failure reasons are stored on the server without any account or purchase identifiers.

## 1.0.6 (build 35 or later)

**Submitted 16 Oct 2026 with build 35 (commit 6a09ab4).** Once Apple releases it: `update public.app_config set latest_build = 35, latest_version = '1.0.6';` (soft update notice). 1.0.5 build 29 (commit 486c752) is the live version and the baseline for rule 3. The backend for everything below (streaks, weekly recap, Psst links, doodles and the 40 KB doodle limit) is deployed to production.

**Before submitting:**
1. Create two fresh review codes for the Psst Team profile:

   ```sql
   insert into public.invites (code, inviter_id, expires_at)
   select v.code, p.id, now() + interval '30 days'
   from public.profiles p, (values ('PSSTFIVE'), ('PSSTCATS')) as v(code)
   where p.display_name = 'Psst Team';
   ```

2. Check `min_build` is not above the build you submit: `select min_build, latest_build, latest_version from public.app_config;`
3. In Vercel, set `PSST_SUPABASE_URL` and `PSST_SUPABASE_ANON_KEY`, so Psst links (psstapp.fun/p/CODE) and invite pages show the sender's first name instead of "Someone".
4. The privacy policy should mention the time zone and the weekly recap before release (see App Privacy below).

**What's New in This Version:**

```
• Doodles! Hold someone's band, draw them something, and it lands on their Home Screen widget. Free
• A Control Center button that sends a Psst without opening the app (iOS 18)
• Group invite codes show who's joined
• Super Psst opens a small card instead of a whole page
• Settings, tidied: everything one tap away
• The weekly recap is now on for everyone (turn it off in Settings)
• A smaller download, faster sending, and fixes
```

**Notes for the reviewer:**

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

What's new in 1.0.6:
- Doodles (free): hold a band → "Doodle for <name>", draw with one finger, then SEND DOODLE. The other person gets a notification ("<name> drew you something") and sees the drawing full screen when they open it; it also shows on their Home Screen widget until they psst back. Doodles only go between two people who have both agreed to connect, are limited to 60 strokes, and are deleted after 30 days like every Psst. On the doodle itself, ••• (top left) offers Hide doodle, Block and Report; holding the sender's band offers Report and Block too.
- Control Center (iOS 18): Control Center → + → Add a Control → Psst → "Psst someone", then pick a person. Tapping it sends a Psst without opening the app. Also available as a Shortcuts action, "Send a Psst".
- Group codes: the invite sheet shows how many people joined a code ("3 of 10 joined · 6 days left") and who.
- Super Psst (tap the nudge mark in a band's corner, or hold → Super Psst) now opens a short card over home instead of a full page; it has the same states as before, including the Psst+ offer and Restore purchase once today's free one is used.
- Settings is now a short front page; People, Notifications, Psst+ and Privacy and help each open their own page. Psst+ (with Restore purchase) is reachable from Settings too.
- Weekly recap is on by default (it was opt-in in 1.0.5): a push notification on Sundays at 6 PM opens a summary of the user's own week. It is only about the user's own Pssts, contains no promotional content, is skipped in weeks with no Pssts, and can be turned off in Settings → Weekly recap.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap "I have a code" and enter:  PSSTFIVE
   (backup code:  PSSTCATS)
3. Tap Connect. A band for "Psst Team" appears on home.
4. Tap the band to send a Psst; tap the cat mark in its corner for a Super Psst. We'll psst you back within a few minutes during review hours. If both of you psst within 10 seconds, both phones show SAME MOMENT.
5. Long-press a notification to use "Psst back" without opening the app.
6. Hold the Psst Team band → "Doodle for Psst Team" to send us a drawing. We'll send you one back too.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable, unchanged): home → "Psst+" next to Settings (or Settings → Psst+) → Unlock, or from the Super Psst card once today's free one is used. It adds unlimited Super Psst, per-person band colours, alternate app icons, whisper sounds and Home Screen / Lock Screen widgets. Doodles, including the doodle shown on the recipient's widget, and the Control Center button are free. "Restore purchase" is on both sheets. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

**App Privacy:** doodles are covered by the existing **User Content → Other User Content** (linked, not tracking, App Functionality); the privacy manifest now lists it too. The device's time zone is now saved on the account (streak days and the recap's Sunday 6 PM). Apple has no time-zone category and it is far coarser than "Coarse Location", so the safe declaration is **Other Data → App Functionality, linked to the user, not used for tracking**. Weekly recap and Psst links collect nothing else new: the recap is computed from Pssts already stored, and a Psst link stores only the same invite row as an invite code.

## 1.0.7 (build 40 or later)

1.0.6 (build 35) is the live version and the baseline for rule 3. Submit with the Release to App Store workflow (version 1.0.7, the newest build, mode prepare to check, then submit); it reads the two blocks below.

**What's New in This Version:**

```
• Your word (Psst+): choose what your people see when you psst them: hey, boop, oi, yo, hiii, mwah or psst psst
• Draw someone new: send a doodle to someone who isn't on Psst yet. It stays sealed until they join
• Psst someone new: with nobody on home yet, one tap shares a Psst link. If it isn't opened in 5 days, we'll remind you once
• Got sent a Psst before you had the app? Paste the link when you pick your name
• Link previews now show who it's from
• The Control Center button asks for Face ID when your iPhone is locked
• Psst+ now unlocks unlimited Super Psst reliably on every iPhone
• Clearer messages and small fixes
```

**Notes for the reviewer:**

```
Psst lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

What's new in 1.0.7:
- Your word (Psst+ only): Psst+ sheet → "Your word" lets the buyer pick one word from a fixed list (psst, hey, boop, oi, yo, hiii, mwah, psst psst). The people they psst then see that word instead of "psst" in the notification ("Mia · boop") and the full-screen moment. It is a fixed list, so there is no free text; the server only accepts these words and only from accounts with a verified Psst+ purchase.
- Psst+ purchases are now verified on our server reliably, so unlimited Super Psst works on every device after buying or restoring.
- Name step: "Someone sent you a Psst?" with Apple's system Paste button. It reads the clipboard only when tapped (no prompt) and only uses a psstapp.fun invite link or code found there.
- Empty home: the gold band shares a one-person Psst link. If nobody opens it within 5 days, the sender gets one notification ("Your Psst hasn't been opened") that reopens the share sheet. Only once per link.
- Draw someone new (+ → Draw someone new): draw a doodle and share it as a one-person link. The web page only says "Utku drew you something" with a sealed picture; the drawing is shown in the app only after the recipient joins with that link. Same safety as doodles between people (hold the band to Block or Report).
- The Control Center / Lock Screen button now requires Face ID or the passcode on a locked iPhone.

To try it with a real person (our team):
1. Open the app, enter any name, and choose whether to allow notifications.
2. On home, tap "I have a code" and enter:  PSSTFIVE
   (backup code:  PSSTCATS)
3. Tap Connect. A band for "Psst Team" appears on home.
4. Tap the band to send a Psst. We'll psst you back within a few minutes during review hours.
5. To see Your word: home → "Psst+" → Unlock (sandbox purchase), then pick a word under "Your word" and psst us; we'll reply so you can see ours.

Safety: hold any band (or Settings → People) to Remove, Block or Report. Reporting also blocks. On a doodle, ••• offers Hide doodle, Block and Report. Settings → Delete account removes all server data immediately.

Psst+ (in-app purchase "psstplus.unlock", non-consumable, unchanged): home → "Psst+" next to Settings (or Settings → Psst+) → Unlock. It adds unlimited Super Psst, per-person band colours, alternate app icons, whisper sounds, Your word and Home Screen / Lock Screen widgets. Doodles and the Control Center button are free. "Restore purchase" is on the Psst+ sheet. Pssting, replies and invites are free.

Privacy policy: https://psstapp.fun/privacy · Terms: https://psstapp.fun/terms · Support: https://psstapp.fun/support
```

**App Privacy:** nothing new to declare: your word is a setting on the account (covered by the existing linked, not tracking, App Functionality items).
