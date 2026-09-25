# App Review: notes and routine

**Owner decision (25 Sep 2026): option A.** The reviewer gets an invite code from a real account on the owner's phone, and the owner pssts back while the app is in review. No demo account or fake contact is built into the app.

## Before each submission

1. Install the **production** TestFlight build on your own iPhone. Start it with a clear display name, e.g. **Psst Team**.
2. On home, tap the gold **+** band → **Share my invite**. Write down the code, then do it once more for a second code, in case two reviewers try.
   - Each code works **once** and expires after **7 days**. Make fresh ones for every submission.
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

For a later submission, pick two new unused codes; each works once.

## While in review

- Keep your phone's notifications **on** for Psst. When the reviewer's Psst arrives, psst back within a few minutes. Try once to psst back within 10 seconds, so they can see SAME MOMENT.
- In the Supabase dashboard, a new connection appears in `public.connections` the moment a code is used. You can also just watch your phone's home screen for a new band.
- After approval, remove the reviewer's band if you like: hold the band → Remove.

## Notes to paste (fill in the two codes)

```
Psst Back lets two people who have both agreed to connect send each other a one-tap "Psst". There is no login: an anonymous account is created when you enter a name.

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
