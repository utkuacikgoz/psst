# Rules for every coding agent (Codex, Claude, others)

Read `CLAUDE.md` and `DESIGN.md` first. These rules come from the owner.

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
   owner asks: they cost the owner money.
5. **Tests: find the cause before changing them.** Get evidence (failure
   annotation or screenshot) first; never "fix" a test by guessing.
