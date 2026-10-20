#!/usr/bin/env python3
"""Fails if an owner-approved feature or design disappears from the app.

Each check names the owner decision (see DESIGN.md) and a marker that must stay
in the code. A merge that drops one fails CI on Linux in seconds. To change an
approved design on purpose, get the owner's approval first, then update the
check here and the decision in DESIGN.md in the same commit.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

CHECKS = [
    # (decision, file, regex that must match)
    ("ED1: Settings opens with your name band", "Psst/Live/SettingsSheet.swift", r"YouBand\(name:"),
    ("ED1: Edit name opens the band editor", "Psst/Live/SettingsSheet.swift", r"NameEditSheet\(\)"),
    ("NM1: first launch asks what your people call you", "Psst/Live/OnboardingViews.swift", r"What do your people call you\?"),
    ("NM1: you type into your own band", "Psst/Live/OnboardingViews.swift", r"struct NameBand"),
    ("I2: invite chooser has Share my invite", "Psst/Live/InviteSheet.swift", r'chooserBand\(title: "Share my invite"'),
    ("I2: invite chooser has I have a code", "Psst/Live/InviteSheet.swift", r'chooserBand\(title: "I have a code"'),
    ("Empty home offers I have a code", "Psst/Live/LiveHomeView.swift", r"haveCodeBand"),
    ("Home loader while people load", "Psst/Live/LiveHomeView.swift", r"loadingPeople"),
    ("People from last time show at launch", "Psst/Live/LiveStore.swift", r"connectionsCacheKey"),
    ("Rating asked once after a happy moment", "Psst/Live/LiveHomeView.swift", r"requestReview"),
    ("Not now can turn notifications on later", "Psst/Live/SettingsSheet.swift", r"Turn on notifications"),
    ("Whisper plays with the app open", "Psst/Live/AppDelegate.swift", r"completionHandler\(\[\.sound\]\)"),
    ("ps-st vibration on arrival", "Psst/ArrivalView.swift", r"PsstHaptics\.play"),
    ("Home Screen widget", "PsstWidget/PsstWidget.swift", r"struct PeopleWidget: Widget"),
    ("Lock Screen widget (owner go 10 Oct)", "PsstWidget/PsstWidget.swift", r"FavouriteWidget"),
    ("Small Home Screen widget free: your #1 person (owner pick 7A, 20 Oct)", "PsstWidget/PsstWidget.swift", r"!entry\.unlocked && family != \.systemSmall"),
    ("Redeem a code in Psst+ (owner pick 8A, 20 Oct)", "Psst/Live/PsstPlusSheet.swift", r"offerCodeRedemption"),
    ("Terms agreed on the name step (owner pick 4A, 20 Oct)", "Psst/Live/OnboardingViews.swift", r"By continuing you agree to the "),
    ("Widget is embedded in the app", "Psst.xcodeproj/project.pbxproj", r"PsstWidget\.appex in Embed"),
    ("Typeface: Inter Tight (owner pick 25 Sep)", "Config/Info.plist", r"InterTight-Black\.ttf"),
    ("Alternate app icons", "Config/Psst.xcconfig", r"AppIcon-Night.*AppIcon-Gold.*AppIcon-Pink|AppIcon-Pink.*AppIcon-Gold.*AppIcon-Night"),
    ("Psst+ whisper sounds", "Psst/Live/PsstPlusSheet.swift", r"psst-double"),
    ("Version at the bottom of Settings (owner pick 13 Oct)", "Psst/Live/SettingsSheet.swift", r"versionLine"),
    ("Pull-down search on home (owner pick 13 Oct)", "Psst/Live/LiveHomeView.swift", r"searchField\(inset:"),
    ("Shimmer on the name while sending (owner pick 13 Oct)", "Psst/PersonRow.swift", r"SendingShimmer\(active: isBusy\)"),
    ("Forced update page (owner pick 13 Oct)", "Psst/Live/LiveHomeView.swift", r"UpdateRequiredView\(\)"),
    ("Soft update notice strip (owner pick 13 Oct)", "Psst/Live/LiveHomeView.swift", r"A new Psst is ready"),
    ("Ps-st pulses when a Psst is sent (owner pick 13 Oct)", "Psst/PersonRow.swift", r"PsstRipple\(trigger: effect\?\.id\)"),
    ("Invite page: Get Psst to the App Store + Smart App Banner (owner pick 13 Oct)", "site/invite.html", r'apple-itunes-app.*id="get"'),
    ("Super Psst sheet Direction A: Psst+ offer when used (owner pick 13 Oct)", "Psst/Live/FeatureViews.swift", r'UNLOCK PSST\+'),
    ("Super Psst corner button on each band: the nudge mark (owner pick 12 Oct; ✦ replaced by nudge 1A, 14 Oct)", "Psst/Live/LiveHomeView.swift", r'NudgeMark\(eyes:'),
    ("The Psst is the invite: PSST SOMEONE NEW band (owner pick 5A, 14 Oct)", "Psst/Live/InviteSheet.swift", r'chooserBand\(title: "Psst someone new"'),
    ("Weekly recap: full-screen recap (owner pick 4A, 14 Oct; on by default since 2A, 16 Oct)", "Psst/Live/FeatureViews.swift", r'struct WeeklyRecapView'),
    ("Streak corner flame from 3 days (owner pick 3A, 14 Oct)", "Psst/PersonRow.swift", r'if streakDays >= 3'),
    ("Cats in the pull gaps: I'm here! / Psst! (owner pick 2A, 14 Oct)", "Psst/Live/LiveHomeView.swift", r'PullCat\(text: "I\'m here!"'),
    ("Super Psst nudge shake on arrival (owner pick 1A, 14 Oct)", "Psst/ArrivalView.swift", r'arrival\.kind == \.superPsst \? trigger : nil'),
    ("Leaderboard podium, all time (owner pick 12 Oct; This month removed 13 Oct)", "Psst/Live/FeatureViews.swift", r'func podiumBand'),
    ("One exchange line with seen, no corner duplicate (owner pick 12 Oct)", "Psst/PersonRow.swift", r'Text\("· seen"\)'),
]

# One signal (owner, 25 Sep): no picker and none of the removed signals.
FORBIDDEN = [
    ("Removed signals stay removed", "Psst/Signal.swift", r"\b(squeeze|oi|duck)\b"),
]


def main():
    failures = []
    for decision, path, pattern in CHECKS:
        text = (ROOT / path).read_text() if (ROOT / path).exists() else ""
        if not re.search(pattern, text, re.S):
            failures.append(f"missing  {decision}  ({path}: /{pattern}/)")
    for decision, path, pattern in FORBIDDEN:
        text = (ROOT / path).read_text() if (ROOT / path).exists() else ""
        if re.search(pattern, text):
            failures.append(f"found    {decision}  ({path}: /{pattern}/)")
    if failures:
        print("Owner-approved features changed without the check being updated:")
        for line in failures:
            print("  " + line)
            print(f"::error::{line}")
        sys.exit(1)
    print(f"All {len(CHECKS) + len(FORBIDDEN)} owner-decision checks pass.")


main()
