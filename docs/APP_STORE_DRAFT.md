# App Store and privacy draft

Draft for review. Grounded in the code as of 25 September 2026. Nothing here has been submitted.

## Listing

- **Name (store):** Psst – Tap a Friend (placeholder; "Psst" alone is taken). The home-screen name stays "Psst".
- **Subtitle (30 chars):** One tap to say you're thinking
- **Category:** Social Networking
- **Keywords:** tap,nudge,yo,thinking of you,friends,couples,poke,hello,psst
- **Description:**

  Tap a person. They get a small signal. They can send one back without typing a thing.

  Every tap sends a Psst: a small signal that says you're thinking of them. There's nothing to type and nothing to choose.

  Connect with someone by sharing an invite link or code. Nothing is sent until you've both accepted. You can remove, block or report anyone at any time, and you can delete your account in Settings.

  No feed, no strangers, no contacts upload, no location.

- **What to test (TestFlight):** Invite a second tester, tap each other, open a notification, and try "Psst back" from the notification. Turn notifications off and check that signals still appear in the app.

## App Privacy ("nutrition label")

Based on what the backend stores (`supabase/migrations`) and what the app sends.

| Data type (Apple's category) | Collected | Linked to the person | Tracking | Purpose |
|---|---|---|---|---|
| Name (Contact Info) | Yes: the display name they choose | Yes | No | App functionality |
| User ID (Identifiers) | Yes: an account ID | Yes | No | App functionality |
| Other User Content | Yes: which signal was sent to which connection, when, and when it was seen | Yes | No | App functionality |
| Everything else (location, contacts, photos, browsing, purchases, usage data, diagnostics, advertising data) | No | | | |

- **Tracking:** none. There are no analytics or advertising SDKs, and no third-party packages at all.
- **Push token:** the device's notification token is stored so the server can send notifications, and deleted when Apple reports it dead or the account is deleted. Apple doesn't list push tokens as a separate category. Decide at submission whether to mention it under Identifiers; the privacy policy mentions it either way.
- **Retention:** signals are deleted after 30 days, and finished invites 30 days after they end.
- **Deletion:** in-app account deletion removes the account and cascades to name, connections, signals, invites and device tokens.

## Privacy policy (draft text)

A privacy policy URL is required before submission. This text needs a public home, such as a GitHub Pages page.

> **Psst privacy policy**
>
> Psst stores only what it needs to deliver signals between people who have both agreed to connect.
>
> - **Your display name**, shown to the people you're connected with.
> - **An account ID**, created anonymously when you start. No email or phone number.
> - **Your connections**, the invites you create, anyone you've blocked, and any reports you make (who you reported and when; there is no message content to include).
> - **Signals**: which signal was sent, to whom, when, and whether it was seen. Kept for 30 days.
> - **Your device's notification token**, so we can send you notifications.
>
> We don't read your contacts, location or photos. We don't use analytics, advertising or tracking, and we don't sell or share your data. The data is stored with our hosting provider (Supabase) and sent to Apple's push notification service to deliver notifications.
>
> You can remove or block anyone, turn notifications off in iOS Settings, and delete your account in Psst's Settings, which deletes all of the above.
>
> Contact: [support email to add]

## Before submission

- A support URL and support email.
- A hosted privacy policy URL.
- A named person who reviews reports (the `reports` table) and acts on them promptly, as guideline 1.2 expects. Reporting already blocks the person in the app.
- The age rating questionnaire: the app lets connected people see each other's chosen names, with no free-text messaging.
- A production Supabase project and a production TestFlight/App Store build pointed at it. TestFlight currently uses the development project.
- Real app icon and screenshots.
