# Launch kit

Drafts to copy, edit into your own voice, and post. Every link carries its campaign (see `CAMPAIGN_LINKS.md`) so App Store Connect shows which post brought installs. Facts here match the shipped app: free, iPhone (iOS 17+), mutual invites only, no feed/chat/contacts/location, no analytics SDK in the app, SAME MOMENT within 10 seconds, optional one-time Psst+.

Before posting anywhere, read that community's self-promotion rules. Post as yourself, answer every comment, and don't ask friends to upvote (Reddit, HN and Product Hunt all penalise it).

## One-liners

- **Short:** Psst — one tap tells someone you're thinking of them.
- **Longer:** Psst is a tiny iPhone app for the few people you care about. Tap their name, they get a "psst", and they can psst you back straight from the notification. No feed, no chat, no typing.

## Reddit

### r/SideProject (self-promo allowed)

**Title:** I rebuilt Yo as a "thinking of you" button for the few people who matter

**Body:**
> Remember Yo, the app that only sent "Yo"? I always liked how little it asked of you, so I built a warmer version for iPhone called Psst.
>
> - You invite someone with a link or code; you're only connected once you both accept.
> - Tap their colour band and they get a "psst" — basically "thinking of you".
> - They can psst back straight from the notification without opening the app.
> - If you both psst each other within 10 seconds you get a SAME MOMENT.
>
> No feed, no chat, no contacts upload, no location. It's free; there's an optional one-time Psst+ for extra colours, sounds and icons.
>
> Built in SwiftUI with a small Supabase backend. Would love blunt feedback — especially on whether the first invite makes sense.
>
> https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&mt=8&ct=reddit

### r/iosapps (check the weekly self-promo thread first)

**Title:** Psst – a one-tap "thinking of you" app (free, no ads, no chat)

**Body:**
> Psst is a one-button app for close friends, family or a partner. Tap their name and they get a psst; they can send one back from the notification. Home Screen and Lock Screen widgets let you psst your favourite person without opening the app. Free; optional one-time Psst+ for colours, sounds and icons.
>
> https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&mt=8&ct=reddit

### r/LongDistance (only if the rules allow app posts; otherwise skip or ask the mods)

**Title:** Made a tiny app for the "thinking of you" moments in long distance

**Body:**
> My partner and I kept sending "🫶" with nothing else to say, so I built something for exactly that. Psst is one tap: your person gets a psst, and they can psst back from the notification. If you both tap within 10 seconds you get a SAME MOMENT. There's a Lock Screen widget so it's one tap from your lock screen. Free, no chat, nothing to keep up with.
>
> https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&mt=8&ct=reddit

(Edit the first line so it's true for you.)

## Show HN

**Title:** Show HN: Psst – Yo, but for "thinking of you"

**Link:** https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&mt=8&ct=showhn

**First comment:**
> Hi HN. Psst is an iPhone app with one action: tap a person and they get a "psst". They can reply from the notification without opening the app. That's the whole product.
>
> Some details that might interest people here:
>
> - Connections are mutual: invite link or code, both sides accept, and the server checks the connection, blocks and rate limits on every send.
> - Each send has an idempotency key, so retries and double taps don't produce duplicate pssts.
> - The app never shows "delivered". APNs accepting a push isn't proof the phone got it, so the sender only sees "sent" until the other person actually opens it ("seen").
> - SAME MOMENT: if both people psst each other within 10 seconds (server timestamps), both get a small celebration.
> - Stack: SwiftUI (iOS 17, no third-party packages), WidgetKit, Supabase Postgres with an edge function that talks to APNs directly.
> - Accounts are anonymous with a display name; no contacts upload, no location, no analytics SDK in the app. You can delete your account from Settings.
>
> It's free. There's an optional one-time "Psst+" for extra colours, sounds and icons; sending and receiving stay free.
>
> I'd especially like feedback on the invite flow — it's where people drop off.

## Product Hunt

- **Name:** Psst – Tap a Friend
- **Tagline (≤60):** One tap tells someone you're thinking of them
- **Topics:** iOS, Social Networking, Productivity (or Relationships)
- **Link:** https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&mt=8&ct=producthunt
- **Description (≤260):** Psst is a one-tap iPhone app for the few people you care about. Tap their name, they get a psst, and they can psst back right from the notification. Mutual invites only. No feed, no chat, no contacts upload. Free, with Home and Lock Screen widgets.
- **Gallery:** the App Store screenshots plus `brand/appstore-header/1920x1280.png` as the cover.
- **Maker comment:**
> Hey Product Hunt 👋
>
> I loved how little Yo asked of you, so I made a warmer version: Psst. One tap on a person sends a psst — "thinking of you". They can psst back from the notification without opening the app, and if you both tap within 10 seconds you get a SAME MOMENT.
>
> It's deliberately small: you only connect with people who accept your invite, and there's no feed or chat to keep up with. It's free; Psst+ is an optional one-time unlock for colours, sounds and icons.
>
> I'd love to know who you'd psst first.

## Short video scripts (15–30 s, vertical)

Film real screens and real reactions; don't fake a notification you didn't receive. End each with the App Store link in bio (`tiktok` / `instagram` campaign).

1. **"The whole app"** — Text on screen: "An app with one button." Tap a friend's band → cut to the other phone buzzing with "psst" → they long-press and tap Psst back → first phone gets it. Caption: "That's it. That's the app."
2. **SAME MOMENT** — Two people on a call or in a room: "3, 2, 1" and both tap. Both screens show SAME MOMENT. Caption: "If you both psst within 10 seconds…"
3. **Long distance** — Split screen, two cities/time zones. One taps from the Lock Screen widget at their morning; the other gets it at night and pssts back. Caption: "For the 'thinking of you' you don't have words for."
4. **Remember Yo?** — Old-phone filter: "In 2014 an app that only said Yo raised a million dollars." Cut to Psst: "So I made the sweet version." Show a send and a psst back.
5. **Mischief** — Someone sitting across the room keeps getting pssted; they look around suspiciously; reveal the friend pretending to read. Caption: "Psst is also for annoying your best friend (gently)."

## Posting order

1. Friends first (`friends` link) so there are real connections and early reviews.
2. Show HN and r/SideProject on a weekday morning US time; stay online for the first 3 hours.
3. Product Hunt on a separate day (00:01 Pacific), with the maker comment posted immediately.
4. Videos throughout; repost whichever one gets the most watch time.
