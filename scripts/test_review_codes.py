#!/usr/bin/env python3
"""Review codes in the release notes: placeholders are filled only when present, and
notes without them never touch the database. No network, no keys:

    python3 scripts/test_review_codes.py
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release  # noqa: E402
import review_codes  # noqa: E402

TEMPLATE = 'Enter:  {REVIEW_CODE}\n   (backup code:  {BACKUP_CODE})\n'


class ReviewCodeTests(unittest.TestCase):
    def test_placeholders_are_replaced_with_the_made_codes(self):
        made = []

        def make():
            made.append(1)
            return "AAAA2222", "BBBB3333"

        filled = release.with_review_codes(TEMPLATE, make)
        self.assertEqual(filled, 'Enter:  AAAA2222\n   (backup code:  BBBB3333)\n')
        self.assertEqual(len(made), 1, "one pair per run")

    def test_notes_without_placeholders_never_touch_the_database(self):
        notes = "No codes here. Psst Team is waiting."
        with mock.patch.object(review_codes, "sql", side_effect=AssertionError("database touched")), \
                mock.patch.object(review_codes, "make", side_effect=AssertionError("codes made")):
            self.assertEqual(release.with_review_codes(notes), notes)

    def test_default_maker_runs_one_query_and_masks_the_codes(self):
        queries = []

        def fake_sql(query):
            queries.append(query)
            return [{"id": "1"}, {"id": "2"}]

        env = {"SUPABASE_ACCESS_TOKEN": "t", "SUPABASE_PROJECT_REF": "r", "GITHUB_ACTIONS": "true"}
        with mock.patch.dict(os.environ, env), mock.patch.object(review_codes, "sql", fake_sql), \
                mock.patch("builtins.print") as printed:
            filled = release.with_review_codes(TEMPLATE)
        self.assertIn("insert into public.invites", queries[0], "revoke and insert in one statement")
        self.assertTrue(all(q.lstrip().startswith("select") for q in queries[1:]), "anything after only reads")
        self.assertNotIn("{REVIEW_CODE}", filled)
        self.assertNotIn("{BACKUP_CODE}", filled)
        review, backup = filled.split("Enter:  ")[1][:8], filled.split("backup code:  ")[1][:8]
        self.assertNotEqual(review, backup)
        for code in (review, backup):
            self.assertTrue(all(c in review_codes.ALPHABET for c in code))
            self.assertIn(f"'{code}'", queries[0])
        output = [" ".join(map(str, c.args)) for c in printed.call_args_list]
        self.assertEqual(output[:2], [f"::add-mask::{review}", f"::add-mask::{backup}"], "masked before anything else")
        self.assertFalse(any(review in line for line in output[2:]), "never printed unmasked")

    def test_missing_profile_or_secrets_stop_the_release(self):
        with mock.patch.dict(os.environ, {"SUPABASE_ACCESS_TOKEN": "t", "SUPABASE_PROJECT_REF": "r"}), \
                mock.patch.object(review_codes, "sql", return_value=[]), mock.patch("builtins.print"):
            with self.assertRaises(SystemExit):
                release.with_review_codes(TEMPLATE)
        with mock.patch.dict(os.environ, {"SUPABASE_ACCESS_TOKEN": "", "SUPABASE_PROJECT_REF": ""}), \
                mock.patch.object(review_codes, "sql", side_effect=AssertionError("database touched")):
            with self.assertRaises(SystemExit):
                release.with_review_codes(TEMPLATE)

    def test_next_release_notes_use_placeholders_and_fit(self):
        _, notes, _ = release.section("1.0.8")
        self.assertIn("{REVIEW_CODE}", notes)
        self.assertIn("{BACKUP_CODE}", notes)
        self.assertNotRegex(notes, r"PSST[A-Z0-9]{4}\b", "no fixed codes in the notes")
        self.assertLessEqual(len(notes), 4000)


if __name__ == "__main__":
    unittest.main(verbosity=1)
