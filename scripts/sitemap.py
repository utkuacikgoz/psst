#!/usr/bin/env python3
"""Writes site/sitemap.xml from the public pages, each dated by its last commit.

Usage: sitemap.py          rewrite site/sitemap.xml
       sitemap.py --check  fail (CI) when it's out of date
"""
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SITE = "https://psstapp.fun"
# Indexable pages only: invite and Psst links are per person and kept out of search.
PAGES = [("/", "site/index.html"), ("/support", "site/support.html"),
         ("/privacy", "site/privacy.html"), ("/terms", "site/terms.html"),
         # Landing pages (owner pick 5A, 19 Oct 2026): one search, one page.
         ("/doodle-widget", "site/doodle-widget.html"),
         ("/long-distance-relationship-app", "site/long-distance-relationship-app.html"),
         ("/couples-widget", "site/couples-widget.html"), ("/yo-app", "site/yo-app.html")]


def last_commit_day(path: str) -> str:
    day = subprocess.run(["git", "log", "-1", "--format=%cs", "--", path], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.strip()
    return day or subprocess.run(["date", "-u", "+%F"], capture_output=True, text=True).stdout.strip()


def sitemap() -> str:
    rows = "".join(f"  <url><loc>{SITE}{url}</loc><lastmod>{last_commit_day(path)}</lastmod></url>\n"
                   for url, path in PAGES)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + rows + "</urlset>\n")


def main():
    target = os.path.join(ROOT, "site", "sitemap.xml")
    wanted = sitemap()
    if "--check" in sys.argv:
        if open(target).read() != wanted:
            sys.exit("site/sitemap.xml is out of date: run python3 scripts/sitemap.py and commit it.")
        print("Sitemap is current.")
        return
    open(target, "w").write(wanted)
    print(wanted, end="")


if __name__ == "__main__":
    main()
