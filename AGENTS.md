# Repository rules

Read `PROJECT.md` and `DESIGN.md` first. These rules come from the owner.

0. **Every design change needs the owner's approval first.** Anything that
   changes how the app, widget or site looks (layout, spacing, type, colour,
   copy on screen, icons, motion) is proposed to the owner with a preview and
   waits for a clear yes before it's committed. The commit then carries a
   `Design-Approved: <what was approved, when>` trailer;
   `scripts/check_design_approval.py` fails CI for any design file changed
   without one. Never write that trailer without the owner's explicit approval
   of that specific change.
   Previews always use the owner's format in docs/DESIGN_PREVIEWS.md: one
   artifact page, numbered topics, A/B/C options with pick buttons on the page.
1. **Never remove or replace an owner-approved feature or design** (anything in
   DESIGN.md marked "owner pick", "owner go", "owner-approved" or
   "Owner-selected") without the owner's explicit approval in the conversation.
   Improving how it works is fine; swapping it for something else is not.
2. **`scripts/check_owner_decisions.py` must pass.** It runs in CI on every push
   and pull request. If an approved change really alters one of its checks,
   update the check and the DESIGN.md entry in the same commit, and say so.
3. **Before merging a branch or another agent's work**, diff every changed view
   against the last released version (git tags / the commit noted in
   docs/APP_REVIEW_NOTES.md) and list, for the owner, anything visible that was
   removed or redesigned.
4. **Don't push code you haven't checked.** If you can't build iOS locally,
   re-read the whole diff for compile errors before pushing; never use CI as
   the compiler. Don't start macOS CI runs (UI tests, screenshots) unless the
   owner asks: they cost the owner money. Exception (owner, 15 Oct 2026): deploy
   the backend and send TestFlight builds without asking, once CI is green on
   what you ship.
5. **Tests: find the cause before changing them.** Get evidence (failure
   annotation or screenshot) first; never "fix" a test by guessing.
6. **Commits are the owner's.** Use `Utku
   <55285576+utkuacikgoz@users.noreply.github.com>` as author and committer.
   Do not add co-author, tool, vendor, or session attribution to commits, PRs,
   or branches. If disclosure is required, use truthful generic wording and do
   not claim the work was done without assistance. Use `work/` for new branch
   names.
