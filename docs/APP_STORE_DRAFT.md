# App Store and privacy draft

Draft for review. Grounded in the code as of 25 September 2026. Nothing here has been submitted.

## Listing

- **Name (store, 26 of 30 chars):** Psst Back: Thinking of You (owner pick, 25 Sep 2026; "Psst" alone is taken). The home-screen name stays "Psst".
- **Subtitle (28 of 30 chars):** One tap. They psst you back.
- **Before committing:** run a trademark search (USPTO, EUIPO) and register psstback.app / psstback.com if free. Domain checks were blocked from the build environment.
- **Category:** Social Networking
- **Keywords:** tap,nudge,yo,friends,couples,poke,hello,whisper,miss you,partner
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
| Other User Content | Yes: which Psst was sent to which connection, when, when it was seen, and whether it was a same moment. Also blocks and reports | Yes | No | App functionality |
| Product Interaction (Usage Data) | Yes: whether notifications are on, and when a pair first pssted both ways. Only daily totals are kept long term | Yes | No | App functionality, Analytics |
| Everything else (location, contacts, photos, browsing, purchases, diagnostics, advertising data) | No | | | |

- **Tracking:** none. There are no analytics or advertising SDKs, and no third-party packages at all. Measurement is done on our own database (`docs/METRICS.md`).
- **Purchases:** Psst+ is bought through Apple. The server never receives purchase data; the app checks the entitlement with StoreKit on the device. So "Purchases" is not collected.
- **Settings:** the chosen whisper sound is stored with the profile so pushes can use it (App functionality). Colours, icon and order stay on the device.
- **Push token:** the device's notification token is stored so the server can send notifications, and deleted when Apple reports it dead or the account is deleted. Apple doesn't list push tokens as a separate category. Decide at submission whether to mention it under Identifiers; the privacy policy mentions it either way.
- **Retention:** signals are deleted after 30 days, and finished invites 30 days after they end.
- **Deletion:** in-app account deletion removes the account and cascades to name, connections, signals, invites and device tokens.

## Privacy policy and support pages

Ready to host in `site/`: `privacy.html`, `support.html` and a small `index.html`. They're grounded in the migrations as of 25 Sep 2026. Before publishing:
1. Replace `SUPPORT_EMAIL` in `site/` with a real support address.
2. Enable GitHub Pages (Settings → Pages → Source: GitHub Actions). This needs a public repository or a paid plan.
3. Run the manual "Publish privacy and support pages" workflow. It refuses to publish while the placeholder remains.

Use the resulting …/privacy.html as the Privacy Policy URL and …/support.html as the Support URL. If you buy psstback.app, point it at the same pages.

## Before submission

- Create the in-app purchase in App Store Connect: non-consumable, product ID `psstplus.unlock`, reference name "Psst+ unlock", with a price tier (the $2.99 hypothesis is unvalidated). Sandbox purchases in TestFlight need it; `Config/PsstPlus.storekit` covers local Xcode runs (Scheme → Run → Options → StoreKit Configuration).

- Publish `site/` (see above) for the Support URL and Privacy Policy URL.
- Reports: the owner reviews the `reports` table regularly (at least weekly) using `docs/REPORTS.md`. Reporting already blocks the person in the app. For the review notes: users can report and block from the long-press menu or Settings → People, and reports are reviewed by the developer.
- The age rating questionnaire: the app lets connected people see each other's chosen names, with no free-text messaging.
- A production Supabase project and a production TestFlight/App Store build pointed at it. TestFlight currently uses the development project.
- App Store screenshots. (The app icon is final: the white "psst" wordmark on purple, approved by the owner on 25 Sep 2026.)
