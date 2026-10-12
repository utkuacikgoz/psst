#!/usr/bin/env python3
"""Fails when a design file changes without the owner's recorded approval.

Every change to how the app or site looks must be approved by the owner first.
A commit that touches a design file must carry a trailer naming that approval:

    Design-Approved: <what the owner approved, and when>

Usage: check_design_approval.py <base-sha> <head-sha>
"""
import re
import subprocess
import sys

DESIGN = re.compile(
    r"^(Psst/(ArrivalView|HomeView|AlexPhoneView|PersonRow|SignalGlyph|DesignTokens|InviteUnavailableSheet)\.swift"
    r"|Psst/Live/(LiveHomeView|OnboardingViews|InviteSheet|SettingsSheet|PsstPlusSheet|FeatureViews|ManageConnection)\.swift"
    r"|Psst/Assets\.xcassets/|Psst/Fonts/|Psst/LaunchScreen\.storyboard"
    r"|PsstWidget/.*\.swift|site/.*\.(html|css)|brand/)"
)


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def main():
    base, head = sys.argv[1], sys.argv[2]
    if set(base) == {"0"}:  # new branch: check just the head commit
        base = head + "~1"
    missing = []
    for sha in git("rev-list", "--no-merges", f"{base}..{head}").split():
        files = git("diff-tree", "--no-commit-id", "--name-only", "-r", sha).split()
        touched = [f for f in files if DESIGN.match(f)]
        if not touched:
            continue
        message = git("log", "-1", "--format=%B", sha)
        if not re.search(r"^Design-Approved: \S", message, re.M):
            subject = message.splitlines()[0]
            missing.append(f"{sha[:7]} {subject}  ({', '.join(touched[:4])}{'…' if len(touched) > 4 else ''})")
    if missing:
        print("Design files changed without the owner's approval recorded (Design-Approved: trailer):")
        for line in missing:
            print("  " + line)
            print(f"::error::Design change without owner approval: {line}")
        sys.exit(1)
    print("Every design change carries the owner's approval.")


main()
