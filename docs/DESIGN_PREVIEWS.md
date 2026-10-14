# Design previews: the owner's format

Owner request (14 Oct 2026): every design proposal comes in this format, every time.

1. **One artifact page per round.** Delete old preview artifacts when asked. Reuse the
   current page's URL for follow-ups in the same round.
2. **Numbered topics: 1, 2, 3 …** Each topic has a number and a heading, so a pick reads as
   "2A, 3B".
3. **Three options per topic: A, B, C**, one marked Recommended, plus "Not now" or "Keep"
   where that makes sense. Sub-choices (e.g. "shake: yes/no", "name: K./Kim/hidden") sit
   under the same number.
4. **Real renders, not descriptions.** Phone frames drawn from the app's own tokens, fonts
   and copy, rendered to images and checked (opened) before sending. Each frame has a
   one-line caption.
5. **Picks are made on the page.** Tap buttons under each topic save to the page's own
   store (db capability, doc `picks/<round>`), plus a free-text "Anything else" box and a
   Copy picks fallback. Claude reads the saved picks from the page instead of asking in chat.
6. Picks are the owner's design approval for exactly what was shown (AGENTS.md rule 0).
   Commits that build them carry `Design-Approved:` naming the picks and the date.
