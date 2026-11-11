#!/usr/bin/env python3
"""Authorization, deduplication, connection/block, invite and token tests.

Runs against a disposable database on any Postgres 15+ server:

    pip install "psycopg[binary]"
    PSST_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/postgres \
        python3 supabase/tests/test_backend.py

It creates and drops its own database. It applies auth_shim.sql (a stand-in for
Supabase's auth schema) followed by every migration in order.
"""
import json
import os
import pathlib
import secrets
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager

import psycopg
from psycopg import errors

ROOT = pathlib.Path(__file__).resolve().parents[1]
ADMIN_URL = os.environ.get(
    "PSST_TEST_DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/postgres")
DB_NAME = f"psst_test_{uuid.uuid4().hex[:8]}"


def db_url(name):
    base, _, _ = ADMIN_URL.rpartition("/")
    return f"{base}/{name}"


def setUpModule():
    with psycopg.connect(ADMIN_URL, autocommit=True) as conn:
        conn.execute(f'create database "{DB_NAME}"')
    with psycopg.connect(db_url(DB_NAME), autocommit=True) as conn:
        conn.execute((ROOT / "tests" / "auth_shim.sql").read_text())
        for migration in sorted((ROOT / "migrations").glob("*.sql")):
            conn.execute(migration.read_text())


def tearDownModule():
    with psycopg.connect(ADMIN_URL, autocommit=True) as conn:
        conn.execute(f'drop database if exists "{DB_NAME}" with (force)')


class Api:
    """Calls the database the way PostgREST would for one caller."""

    def __init__(self, role, user_id=None):
        self.role = role
        self.user_id = user_id

    @contextmanager
    def _cursor(self):
        with psycopg.connect(db_url(DB_NAME)) as conn:
            with conn.cursor() as cur:
                cur.execute(f"set local role {self.role}")
                claims = json.dumps({"sub": str(self.user_id), "role": self.role} if self.user_id else {"role": self.role})
                cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
                yield cur
            conn.commit()

    def rpc(self, fn, *args):
        """Like PostgREST: a function that set response.status >= 400 is a refusal.
        Its transaction still commits (that's why such functions don't raise)."""
        placeholders = ", ".join(["%s"] * len(args))
        with self._cursor() as cur:
            cur.execute(f"select public.{fn}({placeholders})", args)
            result = cur.fetchone()[0]
            cur.execute("select current_setting('response.status', true)")
            status = cur.fetchone()[0]
        if status and int(status) >= 400:
            raise Refusal(int(status), result)
        return result

    def rows(self, sql, *args):
        with self._cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchall()


def admin(sql, *args):
    with psycopg.connect(db_url(DB_NAME), autocommit=True) as conn:
        cur = conn.execute(sql, args)
        return cur.fetchall() if cur.description else None


def new_user(name):
    user_id = admin("insert into auth.users default values returning id")[0][0]
    api = Api("authenticated", user_id)
    api.rpc("set_display_name", name)
    return api


def connect(a, b):
    code = a.rpc("create_invite")["code"]
    return b.rpc("accept_invite", code)["connection_id"]


class Refusal(Exception):
    """A refusal returned with response.status: the HTTP status and body PostgREST sends."""

    def __init__(self, status, body):
        super().__init__(f"{status} {body}")
        self.status, self.body = status, body


def error_message(error):
    """The code the app sees, from a raised PTxxx error or a returned refusal."""
    return error.body["message"] if isinstance(error, Refusal) else error.diag.message_primary


class ErrorCode:
    """Asserts a PostgREST-style error: SQLSTATE PTxxx with a message, or a refusal
    returned with that HTTP status and the same body."""

    def __init__(self, test, message, status):
        self.test, self.message, self.status = test, message, status

    def __enter__(self):
        return self

    def __exit__(self, kind, value, tb):
        self.test.assertIsNotNone(value, f"expected {self.message}")
        if isinstance(value, Refusal):
            self.test.assertEqual(value.status, self.status, str(value))
            self.test.assertEqual(value.body, {"code": f"PT{self.status}", "details": None, "hint": None,
                                               "message": self.message})
            return True
        self.test.assertIsInstance(value, psycopg.Error)
        self.test.assertEqual(value.diag.sqlstate, f"PT{self.status}", str(value))
        self.test.assertEqual(value.diag.message_primary, self.message)
        return True


class BackendTests(unittest.TestCase):
    def fails(self, message, status):
        return ErrorCode(self, message, status)

    # Invites ---------------------------------------------------------------

    def test_open_invites_lists_only_your_usable_ones(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        used = ada.rpc("create_invite")["code"]
        cancelled = ada.rpc("create_invite")["code"]
        expired = ada.rpc("create_invite")["code"]
        open_code = ada.rpc("create_invite")["code"]
        emre.rpc("accept_invite", used)
        admin("update public.invites set max_uses = 1 where code = %s", used)  # now full
        ada.rpc("revoke_invite", cancelled)
        admin("update public.invites set expires_at = now() - interval '1 minute' where code = %s", expired)
        self.assertEqual([r[0] for r in ada.rows("select code from public.list_open_invites()")], [open_code])
        self.assertEqual(sam.rows("select code from public.list_open_invites()"), [], "only your own")
        ada.rpc("revoke_invite", open_code)
        self.assertEqual(ada.rows("select code from public.list_open_invites()"), [])

    def test_invite_progress_shows_the_open_group_code_filling_up(self):
        ada, emre, sam, kim, zed = new_user("Ada"), new_user("Emre"), new_user("Sam"), new_user("Kim"), new_user("Zed")
        self.assertIsNone(ada.rpc("invite_progress"), "nothing until someone joins")
        code = ada.rpc("create_invite")["code"]
        self.assertIsNone(ada.rpc("invite_progress"))
        for person in (emre, sam, kim):
            person.rpc("accept_invite", code)
        progress = ada.rpc("invite_progress")
        self.assertEqual((progress["code"], progress["uses"], progress["max_uses"]), (code, 3, 10))
        self.assertEqual(progress["joined"], ["Emre", "Sam", "Kim"])
        ada.rpc("block_user", str(kim.user_id))
        self.assertEqual(ada.rpc("invite_progress")["joined"], ["Emre", "Sam"], "blocked people aren't named")
        self.assertEqual(ada.rpc("invite_progress")["uses"], 3, "but still count")
        self.assertIsNone(zed.rpc("invite_progress"), "only the inviter's own codes")
        self.assertIsNone(emre.rpc("invite_progress"))
        admin("update public.invites set expires_at = now() - interval '1 minute' where code = %s", code)
        self.assertIsNone(ada.rpc("invite_progress"), "gone once expired")
        with self.assertRaises(psycopg.Error):
            Api("anon").rpc("invite_progress")

    def test_metrics_report_is_counts_only_and_server_only(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        connect(ada, emre)
        admin("select private.snapshot_metrics(current_date)")
        report = Api("service_role").rpc("metrics_report")
        self.assertGreaterEqual(report["accounts_now"], 2)
        self.assertEqual(report["plus_now"], 0)
        today = report["days"][-1]
        self.assertGreaterEqual(today["accepted_invites"], 1)
        self.assertNotIn(str(ada.user_id), json.dumps(report), "no ids")
        self.assertNotIn("Ada", json.dumps(report), "no names")
        for caller in (ada, Api("anon")):
            with self.assertRaises(psycopg.Error):
                caller.rpc("metrics_report")

    def test_doodles_carry_strokes_and_stay_until_answered(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        heart = json.dumps([[[0.2, 0.3], [0.5, 0.8], [0.8, 0.3]], [[0.1, 0.1]]])
        self.assertIsNone(emre.rpc("latest_doodle"))
        ada.rpc("send_signal", uuid.uuid4(), conn, "doodle", heart)
        unseen = emre.rows("select effect_id, doodle from public.list_unseen()")
        self.assertEqual(unseen[0][0], "doodle")
        self.assertEqual(unseen[0][1], json.loads(heart))
        latest = emre.rpc("latest_doodle")
        self.assertEqual((latest["sender_name"], latest["doodle"]), ("Ada", json.loads(heart)))
        self.assertIsNone(ada.rpc("latest_doodle"), "only the recipient sees it")
        self.assertIsNone(sam.rpc("latest_doodle"))
        emre.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertIsNone(emre.rpc("latest_doodle"), "gone once they psst back")
        # The biggest drawing the app allows: 60 strokes, 2,000 points, 3 decimals each.
        biggest = [[[round(0.123 + (i % 7) / 1000, 3), round(0.456 + (i % 5) / 1000, 3)] for i in range(n)] for n in [34] * 20 + [33] * 40]
        self.assertEqual(sum(map(len, biggest)), 2000)
        ada.rpc("send_signal", uuid.uuid4(), conn, "doodle", json.dumps(biggest))
        # Plain sends still work with three arguments, and only doodles may carry a drawing.
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        for bad in (None, "[]", json.dumps([[[1.5, 0.2]]]), json.dumps([[["a", 0.2]]]), json.dumps([[[0.1, 0.1]]] * 61),
                    json.dumps([[[0.5, 0.5]] * 2001])):
            with self.fails("invalid_doodle", 422):
                ada.rpc("send_signal", uuid.uuid4(), conn, "doodle", bad)
        with self.fails("invalid_doodle", 422):
            ada.rpc("send_signal", uuid.uuid4(), conn, "psst", heart)

    def test_invite_accept_creates_mutual_connection(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        code = ada.rpc("create_invite")["code"]
        self.assertEqual(len(code), 8)
        preview = emre.rpc("preview_invite", code.lower()[:4] + "-" + code.lower()[4:])
        self.assertEqual(preview, {"status": "pending", "kind": "code", "inviter_name": "Ada"})
        result = emre.rpc("accept_invite", code)
        self.assertEqual(result["status"], "accepted")
        self.assertEqual(len(ada.rows("select * from public.connections")), 1)
        self.assertEqual(len(emre.rows("select * from public.connections")), 1)
        names = [r[0] for r in ada.rows("select other_name from public.list_connections()")]
        self.assertEqual(names, ["Emre"])

    def test_invite_statuses(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")

        own = ada.rpc("create_invite")["code"]
        self.assertEqual(ada.rpc("preview_invite", own)["status"], "own")
        with self.fails("invite_own", 409):
            ada.rpc("accept_invite", own)

        used = ada.rpc("create_invite")["code"]
        emre.rpc("accept_invite", used)
        admin("update public.invites set max_uses = 1 where code = %s", used)  # a full code
        # Someone else (wrong account) opening an already-used link.
        self.assertEqual(sam.rpc("preview_invite", used), {"status": "used", "kind": "code", "inviter_name": None})
        with self.fails("invite_used", 409):
            sam.rpc("accept_invite", used)
        # The person who accepted it sees they're already connected.
        self.assertEqual(emre.rpc("preview_invite", used)["status"], "already_connected")
        self.assertEqual(emre.rpc("accept_invite", used)["status"], "already_connected")

        revoked = ada.rpc("create_invite")["code"]
        ada.rpc("revoke_invite", revoked)
        with self.fails("invite_revoked", 410):
            sam.rpc("accept_invite", revoked)

        expired = ada.rpc("create_invite")["code"]
        admin("update public.invites set expires_at = now() - interval '1 second' where code = %s", expired)
        self.assertEqual(sam.rpc("preview_invite", expired)["status"], "expired")
        with self.fails("invite_expired", 410):
            sam.rpc("accept_invite", expired)

        with self.fails("invite_invalid", 404):
            sam.rpc("accept_invite", "NOPE2345")

    def test_one_code_joins_up_to_ten_people(self):
        ada = new_user("Ada")
        invite = ada.rpc("create_invite")
        self.assertEqual(invite["max_uses"], 10)
        code = invite["code"]
        friends = [new_user(f"Friend{i}") for i in range(11)]
        connections = [f.rpc("accept_invite", code)["connection_id"] for f in friends[:10]]
        self.assertEqual(len(set(connections)), 10, "each join is its own connection")
        self.assertEqual(friends[10].rpc("preview_invite", code)["status"], "used")
        with self.fails("invite_used", 409):
            friends[10].rpc("accept_invite", code)
        # Joining again is harmless and doesn't use up a place.
        self.assertEqual(friends[0].rpc("accept_invite", code)["status"], "already_connected")
        self.assertEqual(admin("select uses from public.invites where code = %s", code)[0][0], 10)
        self.assertEqual(ada.rows("select code from public.list_open_invites()"), [], "a full code isn't open")
        # Each inviter push names the right person.
        service = Api("service_role")
        self.assertEqual(service.rpc("joined_push_targets", connections[0])["joiner_name"], "Friend0")
        self.assertEqual(service.rpc("joined_push_targets", connections[9])["joiner_name"], "Friend9")

    def test_concurrent_joins_never_pass_the_limit(self):
        ada = new_user("Ada")
        code = ada.rpc("create_invite")["code"]
        admin("update public.invites set max_uses = 3 where code = %s", code)
        friends = [new_user(f"Racer{i}") for i in range(8)]

        def join(friend):
            try:
                return friend.rpc("accept_invite", code)["status"]
            except (psycopg.Error, Refusal) as error:
                return error_message(error)

        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(join, friends))
        self.assertEqual(sorted(results), ["accepted"] * 3 + ["invite_used"] * 5)
        self.assertEqual(admin("select uses from public.invites where code = %s", code)[0][0], 3)

    def test_cancelling_a_used_code_keeps_who_joined(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        code = ada.rpc("create_invite")["code"]
        emre.rpc("accept_invite", code)
        ada.rpc("revoke_invite", code)
        with self.fails("invite_revoked", 410):
            sam.rpc("accept_invite", code)
        self.assertEqual(len(emre.rows("select * from public.list_connections()")), 1)

    def test_a_used_code_stays_open_when_new_ones_are_made(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        group = ada.rpc("create_invite")["code"]
        emre.rpc("accept_invite", group)
        for _ in range(6):
            ada.rpc("create_invite")
        open_codes = {r[0] for r in ada.rows("select code from public.list_open_invites()")}
        self.assertIn(group, open_codes)

    def test_psst_invite_delivers_the_held_psst_and_works_once(self):
        ada, kim, sam = new_user("Ada Lovelace"), new_user("Kim"), new_user("Sam")
        invite = ada.rpc("create_psst_invite")
        self.assertEqual((invite["kind"], invite["max_uses"]), ("psst", 1))
        code = invite["code"]

        anon = Api("anon")
        card = anon.rpc("public_invite_card", code)
        self.assertEqual((card["status"], card["kind"], card["first_name"]), ("pending", "psst", "Ada"), "first name only")
        self.assertEqual(kim.rpc("preview_invite", code)["kind"], "psst")
        self.assertEqual(ada.rows("select kind from public.list_open_invites()"), [("psst",)])

        result = kim.rpc("accept_invite", code)
        self.assertEqual((result["status"], result["held_psst"]), ("accepted", True))
        unseen = kim.rows("select sender_name, effect_id from public.list_unseen()")
        self.assertEqual(unseen, [("Ada Lovelace", "psst")], "Ada's Psst is Kim's first")
        joined = Api("service_role").rpc("joined_push_targets", result["connection_id"])
        self.assertEqual((joined["held_psst"], joined["held_doodle"]), (True, False))

        self.assertEqual(anon.rpc("public_invite_card", code), {"status": "unavailable"}, "nothing shown once used")
        with self.fails("invite_used", 409):
            sam.rpc("accept_invite", code)
        self.assertEqual(ada.rows("select code from public.list_open_invites()"), [])

    def test_doodle_link_stays_sealed_until_they_join(self):
        ada, kim = new_user("Ada"), new_user("Kim")
        heart = json.dumps([[[0.2, 0.3], [0.5, 0.8], [0.8, 0.3]]])
        invite = ada.rpc("create_psst_invite", heart)
        self.assertEqual((invite["kind"], invite["doodle"]), ("psst", True))
        code = invite["code"]

        card = Api("anon").rpc("public_invite_card", code)
        self.assertEqual((card["doodle"], card["first_name"]), (True, "Ada"))
        self.assertNotIn("0.2", json.dumps(card), "the web never sees the strokes")
        self.assertFalse(Api("anon").rpc("public_invite_card", ada.rpc("create_psst_invite")["code"])["doodle"])
        with self.assertRaises(errors.InsufficientPrivilege):
            Api("anon").rows("select doodle from public.invites")

        result = kim.rpc("accept_invite", code)
        self.assertTrue(result["held_psst"])
        unseen = kim.rows("select sender_name, effect_id, doodle from public.list_unseen()")
        self.assertEqual(unseen, [("Ada", "doodle", json.loads(heart))], "the drawing is Kim's first moment")
        self.assertEqual(admin("select doodle from public.invites where code = %s", code), [(None,)], "the link keeps no copy")
        targets = Api("service_role").rpc("joined_push_targets", result["connection_id"])
        self.assertEqual((targets["held_psst"], targets["held_doodle"]), (True, True))

        with self.fails("invalid_doodle", 422):
            ada.rpc("create_psst_invite", json.dumps([[[2, 2]]]))
        cancelled = ada.rpc("create_psst_invite", heart)["code"]
        ada.rpc("revoke_invite", cancelled)
        self.assertEqual(admin("select doodle from public.invites where code = %s", cancelled), [(None,)],
                         "cancelling drops the drawing")
        expired = ada.rpc("create_psst_invite", heart)["code"]
        admin("update public.invites set expires_at = now() - interval '1 minute' where code = %s", expired)
        admin("select private.purge_expired()")
        self.assertEqual(admin("select doodle from public.invites where code = %s", expired), [(None,)])

    def test_making_codes_never_retires_a_waiting_psst(self):
        ada = new_user("Ada")
        waiting = ada.rpc("create_psst_invite")["code"]
        for _ in range(6):
            ada.rpc("create_invite")
        self.assertIn(waiting, {r[0] for r in ada.rows("select code from public.list_open_invites()")})

    def test_unopened_psst_link_reminds_its_sender_once_from_day_five(self):
        ada, kim, sam = new_user("Ada"), new_user("Kim"), new_user("Sam")
        token = "ab" * 32
        ada.rpc("register_device_token", token, "sandbox")
        admin("update public.profiles set notification_sound = 'psst-soft.wav' where id = %s", ada.user_id)
        service = Api("service_role")
        old = new_user("Old")  # an app from before the reminder (build 39): its link waits
        old_code = old.rpc("create_psst_invite")["code"]
        admin("update public.profiles set app_build = 40 where id in (%s, %s)", ada.user_id, sam.user_id)
        admin("update public.profiles set app_build = 39 where id = %s", old.user_id)

        def age(code, days):
            admin("update public.invites set created_at = now() - %s * interval '1 day' where code = %s", float(days), code)

        due = ada.rpc("create_psst_invite")["code"]
        young = ada.rpc("create_psst_invite")["code"]
        accepted = ada.rpc("create_psst_invite")["code"]
        revoked = ada.rpc("create_psst_invite")["code"]
        expired = ada.rpc("create_psst_invite")["code"]
        group = ada.rpc("create_invite")["code"]
        no_phone = sam.rpc("create_psst_invite")["code"]
        age(young, 4.9)
        for code in (due, accepted, revoked, expired, group, no_phone, old_code):
            age(code, 5)
        kim.rpc("accept_invite", accepted)
        ada.rpc("revoke_invite", revoked)
        admin("update public.invites set expires_at = now() - interval '1 minute' where code = %s", expired)

        targets = service.rpc("invite_reminder_targets")
        by_code = {t["code"]: t for t in targets}
        self.assertEqual(set(by_code), {due, no_phone}, "only day-5+ open Psst links, never group codes")
        self.assertEqual(by_code[due]["user_id"], str(ada.user_id))
        self.assertEqual(by_code[due]["sound"], "psst-soft.wav")
        self.assertEqual(by_code[due]["tokens"], [{"token": token, "environment": "sandbox"}])
        self.assertEqual(by_code[no_phone]["tokens"], [], "claimed anyway: one chance per link")
        self.assertEqual(service.rpc("invite_reminder_targets"), [], "once per link")
        admin("update public.profiles set app_build = 40 where id = %s", old.user_id)
        self.assertEqual([t["code"] for t in service.rpc("invite_reminder_targets")], [old_code], "once they update")

        age(young, 5)
        self.assertEqual([t["code"] for t in service.rpc("invite_reminder_targets")], [young])

        # Two runs at once still remind once.
        late = ada.rpc("create_psst_invite")["code"]
        age(late, 6)
        with ThreadPoolExecutor(4) as pool:
            runs = list(pool.map(lambda _: Api("service_role").rpc("invite_reminder_targets"), range(4)))
        self.assertEqual(sorted(t["code"] for run in runs for t in run), [late])

        # A deleted account takes its links with it: no reminder.
        gone = new_user("Gone")
        admin("update public.profiles set app_build = 40 where id = %s", gone.user_id)
        gone_code = gone.rpc("create_psst_invite")["code"]
        age(gone_code, 5)
        admin("delete from auth.users where id = %s", gone.user_id)
        self.assertEqual(service.rpc("invite_reminder_targets"), [])

        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("invite_reminder_targets")
        with self.assertRaises(errors.InsufficientPrivilege):
            Api("anon").rpc("invite_reminder_targets")

    def test_only_inviter_can_revoke(self):
        ada, sam = new_user("Ada"), new_user("Sam")
        code = ada.rpc("create_invite")["code"]
        with self.fails("invite_invalid", 404):
            sam.rpc("revoke_invite", code)

    def test_invite_limit(self):
        ada = new_user("Ada")
        codes = [ada.rpc("create_invite")["code"] for _ in range(6)]
        # A 6th open invite retires the oldest, so sharing never gets stuck.
        open_codes = {r[0] for r in ada.rows("select code from public.list_open_invites()")}
        self.assertEqual(open_codes, set(codes[1:]))
        for _ in range(14):
            ada.rpc("create_invite")
        with self.fails("too_many_invites", 429):
            ada.rpc("create_invite")

    def test_invites_need_a_profile(self):
        user_id = admin("insert into auth.users default values returning id")[0][0]
        with self.fails("profile_required", 409):
            Api("authenticated", user_id).rpc("create_invite")

    # Sending ---------------------------------------------------------------

    def test_recipient_chooses_their_notification_sound(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        event = uuid.uuid4()
        ada.rpc("send_signal", event, conn, "psst")
        service = Api("service_role")
        self.assertEqual(service.rpc("push_targets", event)["sound"], "psst.wav")
        emre.rpc("set_notification_sound", "psst-soft.wav")
        self.assertEqual(service.rpc("push_targets", event)["sound"], "psst-soft.wav")
        # Only Emre's own choice counts, and only known files.
        ada.rpc("set_notification_sound", "psst-quick.wav")
        self.assertEqual(service.rpc("push_targets", event)["sound"], "psst-soft.wav")
        with self.fails("invalid_sound", 422):
            emre.rpc("set_notification_sound", "../evil.caf")
        # The Psst+ sounds added later are accepted too.
        for sound in ("psst-double.wav", "psst-low.wav", "psst-long.wav"):
            emre.rpc("set_notification_sound", sound)
            self.assertEqual(service.rpc("push_targets", event)["sound"], sound)

    def test_daily_metrics_are_aggregate_counts(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        connect(ada, sam)
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertIsNone(admin("select first_two_way_at from public.connections where id = %s", conn)[0][0])
        emre.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertIsNotNone(admin("select first_two_way_at from public.connections where id = %s", conn)[0][0])
        emre.rpc("set_notification_status", False)
        ada.rpc("set_notification_status", True)
        sam.rpc("block_user", ada.user_id)

        admin("select private.snapshot_metrics(current_date)")
        admin("select private.snapshot_metrics(current_date)")  # re-running replaces the day
        row = admin("""select accepted_invites >= 2, signals >= 2, two_way_pairs >= 1, first_two_way_pairs >= 1,
                              blocks >= 1, notifications_off >= 1, notifications_reported >= 2
                       from private.metrics_daily where day = current_date""")
        self.assertEqual(row, [(True, True, True, True, True, True, True)])
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("select * from private.metrics_daily")

    def test_same_moment_within_ten_seconds(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        first = ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertFalse(first["same_moment"])
        second_id = uuid.uuid4()
        second = emre.rpc("send_signal", second_id, conn, "psst")
        self.assertTrue(second["same_moment"])
        # The retry reports the stored value; Ada learns it from her unseen list.
        self.assertTrue(emre.rpc("send_signal", second_id, conn, "psst")["same_moment"])
        self.assertEqual(ada.rows("select same_moment from public.list_unseen()"), [(True,)])
        # Bounded: another answer within the minute is ordinary.
        self.assertFalse(ada.rpc("send_signal", uuid.uuid4(), conn, "psst")["same_moment"])

    def test_same_moment_needs_the_other_person_and_the_window(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertFalse(ada.rpc("send_signal", uuid.uuid4(), conn, "psst")["same_moment"], "not with yourself")
        admin("update public.signal_events set created_at = created_at - interval '11 seconds' where connection_id = %s", conn)
        self.assertFalse(emre.rpc("send_signal", uuid.uuid4(), conn, "psst")["same_moment"], "too late")

    def test_send_and_idempotent_retry(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        event = uuid.uuid4()
        first = ada.rpc("send_signal", event, conn, "psst")
        self.assertFalse(first["duplicate"])
        self.assertEqual(first["push_status"], "pending")
        retry = ada.rpc("send_signal", event, conn, "psst")
        self.assertTrue(retry["duplicate"])
        self.assertEqual(retry["created_at"], first["created_at"])
        self.assertEqual(len(emre.rows("select * from public.signal_events")), 1)
        unseen = emre.rows("select sender_name, effect_id from public.list_unseen()")
        self.assertEqual(unseen, [("Ada", "psst")])

    def test_cannot_send_on_someone_elses_connection(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        with self.fails("not_connected", 403):
            sam.rpc("send_signal", uuid.uuid4(), conn, "psst")

    def test_cannot_hijack_another_senders_event_id(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        event = uuid.uuid4()
        ada.rpc("send_signal", event, connect(ada, emre), "psst")
        with self.fails("invalid_event_id", 422):
            sam.rpc("send_signal", event, connect(sam, emre), "psst")

    def test_unknown_or_paid_effect_is_rejected(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        with self.fails("effect_unavailable", 403):
            ada.rpc("send_signal", uuid.uuid4(), conn, "fireworks")
        admin("insert into public.effects values ('fireworks', 'Fireworks', false, 99)")
        try:
            with self.fails("effect_unavailable", 403):
                ada.rpc("send_signal", uuid.uuid4(), conn, "fireworks")
        finally:
            admin("delete from public.effects where id = 'fireworks'")

    def test_rate_limit_per_recipient(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        for _ in range(10):
            ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        with self.fails("rate_limited", 429):
            ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        # Emre can still reply: the limit is per sender.
        emre.rpc("send_signal", uuid.uuid4(), conn, "psst")
        # A retry of an accepted event is not a new send and is never limited.
        admin("update public.signal_events set created_at = now() - interval '2 minutes'")
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")

    def test_seen_only_by_recipient(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        event = uuid.uuid4()
        ada.rpc("send_signal", event, conn, "psst")
        self.assertEqual(ada.rpc("ack_signals", [event]), 0)  # sender can't mark seen
        self.assertEqual(emre.rpc("ack_signals", [event]), 1)
        self.assertEqual(emre.rpc("ack_signals", [event]), 0)  # idempotent
        row = ada.rows("select last_from_me, last_seen_at is not null, unseen_count from public.list_connections()")
        self.assertEqual(row, [(True, True, 0)])

    def test_only_psst_can_be_sent(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        for removed in ("squeeze", "oi", "duck"):
            with self.fails("effect_unavailable", 403):
                ada.rpc("send_signal", uuid.uuid4(), conn, removed)
        self.assertFalse(ada.rpc("send_signal", uuid.uuid4(), conn, "psst")["duplicate"])
        with self.assertRaises(errors.UndefinedFunction):
            ada.rpc("set_favorite", conn, "psst")

    # Visibility ------------------------------------------------------------

    def test_rls_hides_other_pairs(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertEqual(sam.rows("select * from public.connections"), [])
        self.assertEqual(sam.rows("select * from public.signal_events"), [])
        self.assertEqual(sam.rows("select * from public.invites"), [])
        self.assertEqual(sam.rows("select display_name from public.profiles"), [("Sam",)])
        self.assertEqual(sam.rows("select * from public.list_connections()"), [])
        self.assertEqual(
            sorted(r[0] for r in ada.rows("select display_name from public.profiles")), ["Ada", "Emre"])

    def test_direct_writes_are_denied(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id) "
                     "values (gen_random_uuid(), %s, %s, %s, 'psst')", conn, emre.user_id, ada.user_id)
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("update public.signal_events set seen_at = now()")
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("delete from public.connections")
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("select * from public.device_tokens")

    def test_anonymous_role_cannot_call_anything(self):
        anon = Api("anon")
        with self.assertRaises(errors.InsufficientPrivilege):
            anon.rpc("list_connections")
        with self.assertRaises(errors.InsufficientPrivilege):
            anon.rows("select * from public.profiles")

    def test_unauthenticated_token_is_rejected(self):
        with self.fails("not_authenticated", 401):
            Api("authenticated").rpc("create_invite")

    def test_push_functions_are_server_only(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        event = uuid.uuid4()
        ada.rpc("send_signal", event, connect(ada, emre), "psst")
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rpc("push_targets", event)
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("record_push_result", event, "accepted", [])

    def test_purchase_failure_reasons_are_server_only_and_capped(self):
        service = Api("service_role")
        for i in range(505):
            service.rpc("log_purchase_failure", "verify Production", f"reason {i}")
        rows = service.rows("select * from public.recent_purchase_failures()")
        self.assertEqual(rows[0][2], "reason 504")
        self.assertLessEqual(admin("select count(*) from private.purchase_failures")[0][0], 500)
        ada = new_user("Ada")
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("log_purchase_failure", "x", "y")
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("select * from public.recent_purchase_failures()")

    def test_streak_counts_days_both_pssted_by_their_own_calendar(self):
        import datetime
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        for person in (ada, emre, sam):
            person.rpc("set_time_zone", "Europe/Istanbul")
        today = datetime.datetime.now(datetime.timezone.utc).replace(hour=9, minute=0, second=0, microsecond=0)

        def psst(conn, sender, recipient, days_ago):
            admin("insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, created_at) "
                  "values (gen_random_uuid(), %s, %s, %s, 'psst', %s)",
                  conn, sender.user_id, recipient.user_id, today - datetime.timedelta(days=days_ago))

        def streak(viewer, conn):
            return [r[0] for r in viewer.rows("select streak_days from public.list_connections() where connection_id = %s", conn)][0]

        pair = connect(ada, emre)
        psst(pair, ada, emre, 2); psst(pair, emre, ada, 2)   # day 1
        psst(pair, ada, emre, 1)                             # only one side so far
        self.assertEqual(streak(ada, pair), 0, "day 1 was the day before yesterday, yesterday isn't complete")
        psst(pair, emre, ada, 1)                             # day 2: yesterday complete
        self.assertEqual(streak(ada, pair), 2, "alive today: it can still go on")
        psst(pair, ada, emre, 0); psst(pair, ada, emre, 0); psst(pair, emre, ada, 0)  # day 3, extra Pssts count once
        self.assertEqual(streak(ada, pair), 3)
        self.assertEqual(streak(emre, pair), 3, "the same for both")

        # A missed day ends it; an old streak isn't shown.
        old = connect(ada, sam)
        psst(old, ada, sam, 5); psst(old, sam, ada, 5); psst(old, ada, sam, 4); psst(old, sam, ada, 4)
        self.assertEqual(streak(ada, old), 0)
        psst(old, ada, sam, 0); psst(old, sam, ada, 0)
        self.assertEqual(streak(ada, old), 1, "starts again from one")

        with self.fails("invalid_time_zone", 400):
            ada.rpc("set_time_zone", "Mars/Base")
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rows("select time_zone from public.profiles")

    def test_weekly_recap_counts_the_week_and_knows_a_new_number_one(self):
        import datetime
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        with_emre, with_sam = connect(ada, emre), connect(ada, sam)
        today = datetime.date.today()
        sunday = today + datetime.timedelta(days=(6 - today.weekday()))  # this week's Sunday (UTC)
        saturday = datetime.datetime.combine(sunday - datetime.timedelta(days=1), datetime.time(12), datetime.timezone.utc)

        def psst(conn, sender, recipient, n, at=saturday):
            for _ in range(n):
                admin("insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, created_at) "
                      "values (gen_random_uuid(), %s, %s, %s, 'psst', %s)", conn, sender.user_id, recipient.user_id, at)

        psst(with_emre, ada, emre, 3); psst(with_emre, emre, ada, 2); psst(with_sam, ada, sam, 1)
        psst(with_sam, sam, ada, 9, at=saturday - datetime.timedelta(days=7))  # last week: not counted

        recap = admin("select private.recap_for(%s, %s)", ada.user_id, sunday)[0][0]
        self.assertEqual((recap["total"], recap["sent"], recap["received"]), (6, 4, 2))
        self.assertEqual((recap["top"]["name"], recap["top"]["count"], recap["top"]["still"]), ("Emre", 5, False))

        # Last week's recap named Sam: Emre is the new #1; had it named Emre, "still".
        admin("insert into private.recap_state (user_id, last_week, last_top) values (%s, %s, %s)",
              ada.user_id, sunday - datetime.timedelta(days=7), with_sam)
        self.assertFalse(admin("select private.recap_for(%s, %s)", ada.user_id, sunday)[0][0]["top"]["still"])
        admin("update private.recap_state set last_top = %s where user_id = %s", with_emre, ada.user_id)
        self.assertTrue(admin("select private.recap_for(%s, %s)", ada.user_id, sunday)[0][0]["top"]["still"])

        self.assertEqual(ada.rpc("weekly_recap_status")["enabled"], True, "on from the start")
        ada.rpc("set_weekly_recap", False)
        self.assertEqual(ada.rpc("weekly_recap_status")["enabled"], False)

        service = Api("service_role")
        self.assertFalse(service.rpc("recap_cron_ok", "guess"), "no vault here: never true")
        with self.fails("scheduler_unavailable", 503):
            service.rpc("schedule_weekly_recap", "https://example.invalid/functions/v1/weekly-recap")
        for fn, args in (("recap_push_targets", ()), ("recap_cron_ok", ("x",))):
            with self.assertRaises(errors.InsufficientPrivilege):
                ada.rpc(fn, *args)

    def test_inviter_hears_who_joined_server_only(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        token = "cd" * 32
        ada.rpc("register_device_token", token, "sandbox")
        emre.rpc("register_device_token", "ef" * 32, "sandbox")
        connection = connect(ada, emre)
        service = Api("service_role")
        targets = service.rpc("joined_push_targets", connection)
        self.assertEqual(targets["joiner_name"], "Emre")
        # Only the inviter's phone, never the person who accepted.
        self.assertEqual(targets["tokens"], [{"token": token, "environment": "sandbox"}])
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("joined_push_targets", connection)
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rpc("remove_device_tokens", [token])
        service.rpc("remove_device_tokens", [token])
        self.assertEqual(service.rpc("joined_push_targets", connection)["tokens"], [])

    def test_invite_guessing_is_limited_per_hour(self):
        ada, sam, kim = new_user("Ada"), new_user("Sam"), new_user("Kim")
        good = ada.rpc("create_invite")["code"]
        # Looking at a code that works isn't a miss.
        for _ in range(25):
            self.assertEqual(sam.rpc("preview_invite", good)["status"], "pending")
        # Misses count from both preview and accept, and accept's count is kept
        # even though it refuses (that's why it returns its refusal instead of raising).
        for i in range(10):
            self.assertEqual(sam.rpc("preview_invite", f"NOPE{i:04d}")["status"], "invalid")
            with self.fails("invite_invalid", 404):
                sam.rpc("accept_invite", f"MISS{i:04d}")
        self.assertEqual(admin("select failures from private.invite_attempts where key = %s", str(sam.user_id)), [(20,)])
        with self.fails("too_many_attempts", 429):
            sam.rpc("preview_invite", good)
        with self.fails("too_many_attempts", 429):
            sam.rpc("accept_invite", good)
        self.assertEqual(sam.rows("select * from public.connections"), [], "blocked even for a good code")
        # Someone else isn't affected.
        self.assertEqual(kim.rpc("accept_invite", good)["status"], "accepted")
        # Used up, cancelled and expired codes are misses too.
        used = ada.rpc("create_psst_invite")["code"]
        kim2 = new_user("Kim2")
        new_user("Zed").rpc("accept_invite", used)
        with self.fails("invite_used", 409):
            kim2.rpc("accept_invite", used)
        self.assertEqual(kim2.rpc("preview_invite", used)["status"], "used")
        self.assertEqual(admin("select failures from private.invite_attempts where key = %s", str(kim2.user_id)), [(2,)])
        # The next hour starts again, and the purge drops old counts.
        admin("update private.invite_attempts set window_start = window_start - interval '1 hour' where key = %s",
              str(sam.user_id))
        self.assertEqual(sam.rpc("accept_invite", good)["status"], "accepted")
        admin("update private.invite_attempts set window_start = now() - interval '25 hours' where key = %s",
              str(sam.user_id))
        admin("select private.purge_expired()")
        self.assertEqual(admin("select count(*) from private.invite_attempts where key = %s", str(sam.user_id)), [(0,)])
        with self.assertRaises(errors.InsufficientPrivilege):
            sam.rows("select * from private.invite_attempts")

    def test_invite_codes_use_every_letter_evenly(self):
        alphabet = "ABCDEFGHJKMNPQRSTVWXYZ23456789"
        codes = [r[0] for r in admin("select private.new_invite_code() from generate_series(1, 7500)")]
        self.assertTrue(all(len(c) == 8 and set(c) <= set(alphabet) for c in codes))
        letters = "".join(codes)
        expected = len(letters) / 30
        chi2 = sum((letters.count(ch) - expected) ** 2 / expected for ch in alphabet)
        # 29 degrees of freedom: about 29 for a fair draw; the old uuid-byte draw gave over 1,000 here.
        self.assertLess(chi2, 75, f"chi-square {chi2:.1f}")

    # Widget ----------------------------------------------------------------

    def test_widget_token_reads_the_doodle_and_people(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        ae, as_ = connect(ada, emre), connect(ada, sam)
        anon = Api("anon")
        emre_token, ada_token = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        emre.rpc("register_widget_token", emre_token)
        ada.rpc("register_widget_token", ada_token)
        self.assertEqual(admin("select count(*) from private.widget_tokens where token_hash = convert_to(%s, 'UTF8')",
                               emre_token), [(0,)], "only the hash is stored")

        self.assertEqual(anon.rpc("widget_state", emre_token),
                         {"doodle": None, "people": [{"connection_id": ae, "last_received_at": None, "streak_days": 0}]})

        heart = json.dumps([[[0.2, 0.3], [0.5, 0.8]]])
        ada.rpc("send_signal", uuid.uuid4(), ae, "doodle", heart)
        state = anon.rpc("widget_state", emre_token)
        latest = emre.rpc("latest_doodle")
        self.assertEqual(state["doodle"], latest, "exactly what latest_doodle gives the app")
        self.assertEqual(set(latest), {"event_id", "connection_id", "sender_name", "created_at", "doodle"})
        self.assertEqual(state["people"], [{"connection_id": ae, "last_received_at": latest["created_at"], "streak_days": 0}])

        # Ada's side: her own sends don't count as received; Emre's reply does, and
        # a day both pssted is a streak (list_connections' number).
        people = {p["connection_id"]: p for p in anon.rpc("widget_state", ada_token)["people"]}
        self.assertEqual(set(people), {ae, as_})
        self.assertIsNone(people[ae]["last_received_at"])
        emre.rpc("send_signal", uuid.uuid4(), ae, "psst")
        state = anon.rpc("widget_state", ada_token)
        people = {p["connection_id"]: p for p in state["people"]}
        received = admin("select to_jsonb(max(created_at)) from public.signal_events where sender_id = %s", emre.user_id)[0][0]
        self.assertEqual(people[ae]["last_received_at"], received)
        streak = ada.rows("select streak_days from public.list_connections() where connection_id = %s", ae)[0][0]
        self.assertEqual((people[ae]["streak_days"], streak), (1, 1))
        self.assertEqual((people[as_]["last_received_at"], people[as_]["streak_days"]), (None, 0))
        self.assertIsNone(state["doodle"])
        self.assertIsNone(anon.rpc("widget_state", emre_token)["doodle"], "answered doodles leave the widget")

        # Unknown, malformed and missing tokens read nothing, with no detail.
        for token in (secrets.token_urlsafe(32), "short", "x" * 129, None):
            self.assertIsNone(anon.rpc("widget_state", token))
        # A token is only ever its own account's: it can't be claimed by someone else.
        with self.fails("invalid_token", 422):
            sam.rpc("register_widget_token", ada_token)
        self.assertEqual(set(p["connection_id"] for p in anon.rpc("widget_state", ada_token)["people"]), {ae, as_})
        for bad in ("short", "x" * 129):
            with self.fails("invalid_token", 422):
                sam.rpc("register_widget_token", bad)
        with self.assertRaises(errors.InsufficientPrivilege):
            anon.rpc("register_widget_token", secrets.token_urlsafe(32))
        with self.fails("not_authenticated", 401):
            Api("authenticated").rpc("register_widget_token", secrets.token_urlsafe(32))
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rows("select * from private.widget_tokens")

        # Registering again replaces the old token.
        newer = secrets.token_urlsafe(48)
        emre.rpc("register_widget_token", newer)
        self.assertIsNone(anon.rpc("widget_state", emre_token))
        self.assertEqual(anon.rpc("widget_state", newer)["people"][0]["connection_id"], ae)

        # Blocking takes the person (and their doodle) off the widget.
        ada.rpc("send_signal", uuid.uuid4(), ae, "doodle", heart)
        self.assertIsNotNone(anon.rpc("widget_state", newer)["doodle"])
        emre.rpc("block_user", ada.user_id)
        self.assertEqual(anon.rpc("widget_state", newer), {"doodle": None, "people": []})

        # Deleting the account ends its token.
        admin("delete from auth.users where id = %s", emre.user_id)
        self.assertIsNone(anon.rpc("widget_state", newer))
        self.assertEqual(admin("select count(*) from private.widget_tokens where user_id = %s", emre.user_id), [(0,)])

    # Names -----------------------------------------------------------------

    def test_display_names_are_cleaned(self):
        ada = new_user("Ada")

        def saved(raw):
            ada.rpc("set_display_name", raw)
            return admin("select display_name from public.profiles where id = %s", ada.user_id)[0][0]

        self.assertEqual(saved("  Ada‮​ \n\t Love⁦lace\u0007 "), "Ada Lovelace")
        self.assertEqual(saved("Kim Lee"), "Kim Lee")
        self.assertEqual(saved("﻿Mia 　Rose‏"), "Mia Rose")
        family = "\U0001F468‍\U0001F469‍\U0001F467 Kim"
        self.assertEqual(saved(family), family, "joiners inside emoji stay")
        self.assertEqual(saved("‍Kim‍‍ ‌Lee"), "Kim Lee")
        self.assertEqual(saved("می‌خواهم"), "می‌خواهم",
                         "a non-joiner inside a Persian word stays")
        self.assertEqual(saved("A" * 40 + "​" * 10), "A" * 40, "invisible padding doesn't count")
        for bad in ("​⁦ㅤ", " \n ", "‮", "B" * 41, ""):
            with self.fails("invalid_name", 422):
                ada.rpc("set_display_name", bad)
        self.assertEqual(admin("select display_name from public.profiles where id = %s", ada.user_id)[0][0], "A" * 40)

    # Measurement -----------------------------------------------------------

    def test_invited_or_organic_survives_the_invite_purge(self):
        def today():
            admin("select private.snapshot_metrics(current_date)")
            return admin("""select invited_new_accounts, organic_new_accounts, code_invites_created,
                                   psst_invites_created from private.metrics_daily where day = current_date""")[0]

        before = today()
        ada, sam = new_user("Ada"), new_user("Sam")                 # organic
        emre, kim = new_user("Emre"), new_user("Kim")               # invited: a code, a Psst link
        emre.rpc("accept_invite", ada.rpc("create_invite")["code"])
        kim.rpc("accept_invite", ada.rpc("create_psst_invite")["code"])
        old = new_user("Old")                                       # joined with an invite days after
        admin("update public.profiles set created_at = now() - interval '3 days' where id = %s", old.user_id)
        old.rpc("accept_invite", sam.rpc("create_invite")["code"])
        after = today()
        self.assertEqual([a - b for a, b in zip(after, before)], [2, 2, 2, 1])

        origins = dict((str(r[0]), r[1:]) for r in admin(
            "select user_id, invited, invite_kind from private.account_origins where user_id = any(%s)",
            [emre.user_id, kim.user_id, old.user_id, ada.user_id]))
        self.assertEqual(origins, {str(emre.user_id): (True, "code"), str(kim.user_id): (True, "psst"),
                                   str(old.user_id): (False, None)})
        # Only the first join counts.
        emre.rpc("accept_invite", sam.rpc("create_psst_invite")["code"])
        self.assertEqual(admin("select invite_kind from private.account_origins where user_id = %s", emre.user_id),
                         [("code",)])

        admin("update public.invites set expires_at = now() - interval '31 days' where inviter_id in (%s, %s)",
              ada.user_id, sam.user_id)
        admin("select private.purge_expired()")
        self.assertEqual(admin("select count(*) from public.invites where inviter_id = %s", ada.user_id), [(0,)])
        self.assertEqual(today()[:2], after[:2], "still told apart once the invites are gone")

        day = Api("service_role").rpc("metrics_report")["days"][-1]
        self.assertEqual(day["invited_new_accounts"], after[0])
        self.assertIn("psst_invites_created", day)
        self.assertNotIn(str(emre.user_id), json.dumps(Api("service_role").rpc("metrics_report")))
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rows("select * from private.account_origins")
        admin("delete from auth.users where id = %s", emre.user_id)
        self.assertEqual(admin("select count(*) from private.account_origins where user_id = %s", emre.user_id), [(0,)])

    # Blocking and removal --------------------------------------------------

    def test_block_removes_connection_and_prevents_reconnecting(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        emre.rpc("block_user", ada.user_id)
        self.assertEqual(ada.rows("select * from public.connections"), [])
        with self.fails("not_connected", 403):
            ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        # Ada's new invite looks invalid to Emre and vice versa.
        code = ada.rpc("create_invite")["code"]
        self.assertEqual(emre.rpc("preview_invite", code), {"status": "invalid", "kind": "code", "inviter_name": None})
        with self.fails("invite_invalid", 404):
            emre.rpc("accept_invite", code)
        code = emre.rpc("create_invite")["code"]
        with self.fails("invite_invalid", 404):
            ada.rpc("accept_invite", code)
        # Ada cannot tell she is blocked from the table either.
        self.assertEqual(ada.rows("select * from public.blocks"), [])
        self.assertEqual(emre.rows("select display_name from public.list_blocked()"), [("Ada",)])

        emre.rpc("unblock_user", ada.user_id)
        self.assertEqual(emre.rpc("accept_invite", ada.rpc("create_invite")["code"])["status"], "accepted")

    def test_report_records_and_blocks(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        emre.rpc("report_user", ada.user_id)
        emre.rpc("report_user", ada.user_id)  # a repeat adds nothing
        self.assertEqual(admin("select count(*) from public.reports where reported_id = %s", ada.user_id), [(1,)])
        with self.fails("not_connected", 403):
            ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        self.assertEqual(emre.rows("select display_name from public.list_blocked()"), [("Ada",)])
        # Neither side can read reports.
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rows("select * from public.reports")
        with self.fails("invalid_user", 422):
            emre.rpc("report_user", emre.user_id)

    def test_report_keeps_the_doodle_before_blocking(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        rude, later = json.dumps([[[0.1, 0.1], [0.9, 0.9]]]), json.dumps([[[0.5, 0.5]]])
        reported_event = uuid.uuid4()
        ada.rpc("send_signal", reported_event, conn, "doodle", rude)
        ada.rpc("send_signal", uuid.uuid4(), conn, "doodle", later)
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        # The app's ••• on a doodle can name it; it's kept even though blocking deletes it.
        emre.rpc("report_user", ada.user_id, reported_event)
        (event_id, evidence, name), = admin(
            "select event_id, evidence, reported_name from public.reports where reported_id = %s", ada.user_id)
        self.assertEqual((event_id, name), (reported_event, "Ada"))
        self.assertEqual((evidence["effect"], evidence["doodle"]), ("doodle", json.loads(rude)))
        self.assertIn("created_at", evidence)
        self.assertEqual(admin("select count(*) from public.signal_events where connection_id = %s", conn), [(0,)],
                         "the block still deletes the Pssts themselves")

        # The shipped app sends only the person: their latest doodle to the reporter is kept.
        # Someone else's event, or one the reporter sent, never becomes the evidence.
        kim = new_user("Kim")
        ada_kim, sam_kim = connect(ada, kim), connect(sam, kim)
        latest, own, others = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        ada.rpc("send_signal", uuid.uuid4(), ada_kim, "doodle", rude)
        ada.rpc("send_signal", latest, ada_kim, "doodle", later)
        ada.rpc("send_signal", uuid.uuid4(), ada_kim, "psst")
        kim.rpc("send_signal", own, ada_kim, "doodle", rude)
        sam.rpc("send_signal", others, sam_kim, "doodle", rude)
        kim.rpc("report_user", ada.user_id, others)
        self.assertEqual(admin("select event_id, evidence->'doodle' from public.reports where reporter_id = %s",
                               kim.user_id), [(latest, json.loads(later))])
        sam.rpc("report_user", kim.user_id, own)  # Kim's doodle went to Ada, not to Sam
        self.assertEqual(admin("select event_id from public.reports where reporter_id = %s", sam.user_id), [(None,)])

        # Nothing to keep: no doodle within 30 days.
        zed = new_user("Zed")
        ada_zed = connect(ada, zed)
        ada.rpc("send_signal", old := uuid.uuid4(), ada_zed, "doodle", rude)
        admin("update public.signal_events set created_at = now() - interval '31 days' where id = %s", old)
        zed.rpc("report_user", ada.user_id)
        self.assertEqual(admin("select event_id, evidence, reported_name from public.reports where reporter_id = %s",
                               zed.user_id), [(None, None, "Ada")])

        # Nobody can read or touch reports from the app, including the reported person.
        for caller in (emre, ada, Api("anon")):
            with self.assertRaises(errors.InsufficientPrivilege):
                caller.rows("select * from public.reports")
            with self.assertRaises(errors.InsufficientPrivilege):
                caller.rows("update public.reports set notified_at = now()")
            with self.assertRaises(errors.InsufficientPrivilege):
                caller.rows("delete from public.reports")
        with self.assertRaises(psycopg.Error):
            Api("anon").rpc("report_user", ada.user_id)

    def test_report_survives_account_deletion_for_ninety_days(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        ada.rpc("send_signal", uuid.uuid4(), conn, "doodle", json.dumps([[[0.2, 0.2]]]))
        emre.rpc("report_user", ada.user_id)
        report = admin("select id from public.reports where reported_id = %s", ada.user_id)[0][0]
        admin("delete from auth.users where id = %s", ada.user_id)
        admin("delete from auth.users where id = %s", emre.user_id)
        self.assertEqual(admin("select reporter_id, reported_id, reported_name, evidence->'doodle' "
                               "from public.reports where id = %s", report),
                         [(None, None, "Ada", [[[0.2, 0.2]]])])
        admin("update public.reports set created_at = now() - interval '89 days' where id = %s", report)
        admin("select private.purge_expired()")
        self.assertEqual(admin("select count(*) from public.reports where id = %s", report), [(1,)])
        admin("update public.reports set created_at = now() - interval '91 days' where id = %s", report)
        admin("select private.purge_expired()")
        self.assertEqual(admin("select count(*) from public.reports where id = %s", report), [(0,)])

    def test_remove_connection(self):
        ada, emre, sam = new_user("Ada"), new_user("Emre"), new_user("Sam")
        conn = connect(ada, emre)
        with self.fails("not_connected", 403):
            sam.rpc("remove_connection", conn)
        emre.rpc("remove_connection", conn)
        self.assertEqual(ada.rows("select * from public.connections"), [])

    # Device tokens ---------------------------------------------------------

    def test_device_token_moves_between_accounts_and_is_cleaned(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        token = "ab" * 32
        ada.rpc("register_device_token", token, "sandbox")
        emre.rpc("register_device_token", token, "sandbox")
        self.assertEqual(admin("select user_id from public.device_tokens where token = %s", token),
                         [(emre.user_id,)])
        with self.fails("invalid_token", 422):
            ada.rpc("register_device_token", "not-a-token", "sandbox")

        event = uuid.uuid4()
        ada.rpc("send_signal", event, connect(ada, emre), "psst")
        service = Api("service_role")
        targets = service.rpc("push_targets", event)
        self.assertEqual(targets["sender_name"], "Ada")
        self.assertEqual(targets["tokens"], [{"token": token, "environment": "sandbox"}])
        service.rpc("record_push_result", event, "failed", [token])
        self.assertEqual(admin("select count(*) from public.device_tokens")[0][0], 0)

    def test_token_limit_per_person(self):
        ada = new_user("Ada")
        for i in range(12):
            ada.rpc("register_device_token", f"{i:064x}", "production")
        self.assertEqual(
            admin("select count(*) from public.device_tokens where user_id = %s", ada.user_id)[0][0], 10)

    # Deletion and retention ------------------------------------------------

    def test_account_deletion_cascades(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        conn = connect(ada, emre)
        ada.rpc("send_signal", uuid.uuid4(), conn, "psst")
        ada.rpc("register_device_token", "cd" * 32, "sandbox")
        ada.rpc("create_invite")
        admin("delete from auth.users where id = %s", ada.user_id)
        for table in ("profiles", "connections", "signal_events", "device_tokens", "invites"):
            self.assertEqual(
                admin(f"select count(*) from public.{table} where %s::uuid in "
                      + {"profiles": "(id)", "connections": "(user_a, user_b)",
                         "signal_events": "(sender_id, recipient_id)",
                         "device_tokens": "(user_id)", "invites": "(inviter_id)"}[table],
                      ada.user_id)[0][0], 0, table)
        self.assertEqual(emre.rows("select * from public.list_connections()"), [])

    def test_purge_removes_old_signals(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        event = uuid.uuid4()
        ada.rpc("send_signal", event, connect(ada, emre), "psst")
        admin("update public.signal_events set created_at = now() - interval '31 days' where id = %s", event)
        admin("select private.purge_expired()")
        self.assertEqual(admin("select count(*) from public.signal_events where id = %s", event)[0][0], 0)


    def test_super_daily_limit_is_global_and_retry_is_idempotent(self):
        a, b, c = new_user("Sender"), new_user("B"), new_user("C")
        ab, ac = connect(a, b), connect(a, c)
        event = uuid.uuid4()
        a.rpc("send_signal", event, ab, "super_psst")
        self.assertTrue(a.rpc("send_signal", event, ab, "super_psst")["duplicate"])
        with self.fails("super_daily_limit", 409):
            a.rpc("send_signal", uuid.uuid4(), ac, "super_psst")
        a.rpc("send_signal", uuid.uuid4(), ac, "psst")
        a.rpc("remove_connection", ab)
        with self.fails("super_daily_limit", 409):
            a.rpc("send_signal", uuid.uuid4(), ac, "super_psst")
        self.assertEqual(a.rpc("super_allowance")["remaining"], 0)
        admin("update private.super_usage set day = day - 1 where user_id = %s", a.user_id)
        self.assertEqual(a.rpc("super_allowance")["remaining"], 1)
        a.rpc("send_signal", uuid.uuid4(), ac, "super_psst")

    def test_concurrent_super_requests_accept_exactly_one(self):
        a, b, c = new_user("Sender"), new_user("B"), new_user("C")
        pairs = [connect(a, b), connect(a, c)]
        def send(pair):
            try:
                a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
                return "sent"
            except (psycopg.Error, Refusal) as error:
                return error_message(error)
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertCountEqual(list(pool.map(send, pairs)), ["sent", "super_daily_limit"])

    def test_verified_plus_cannot_be_forged_or_shared_and_expiry_restores_limit(self):
        a, b = new_user("A"), new_user("B")
        pair = connect(a, b)
        with self.assertRaises(errors.InsufficientPrivilege):
            a.rpc("record_verified_plus", a.user_id, "transaction", True)
        admin("select public.record_verified_plus(%s,%s,true)", a.user_id, str(uuid.uuid4()))
        self.assertTrue(a.rpc("super_allowance")["unlimited"])
        for _ in range(2): a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
        original = admin("select original_transaction_id from private.plus_entitlements where user_id=%s", a.user_id)[0][0]
        # The same purchase on another account (iPad, new phone) works there too...
        admin("select public.record_verified_plus(%s,%s,true)", b.user_id, original)
        self.assertTrue(b.rpc("super_allowance")["unlimited"])
        self.assertTrue(a.rpc("super_allowance")["unlimited"])
        # ...on up to 3 accounts: a 4th evicts the one checked longest ago.
        c, d = new_user("C"), new_user("D")
        admin("update private.plus_entitlements set verified_at=now()-interval '1 hour' where user_id=%s", a.user_id)
        for other in (c, d):
            admin("select public.record_verified_plus(%s,%s,true)", other.user_id, original)
        self.assertFalse(a.rpc("super_allowance")["unlimited"], "evicted: oldest check of four")
        self.assertTrue(d.rpc("super_allowance")["unlimited"])
        with self.assertRaises(errors.InsufficientPrivilege):
            a.rpc("plus_is_current", a.user_id)
        self.assertTrue(admin("select public.plus_is_current(%s)", b.user_id)[0][0])
        # Valid for days, but Apple is asked again after 6 hours.
        admin("update private.plus_entitlements set verified_at=now()-interval '7 hours' where user_id=%s", b.user_id)
        self.assertFalse(admin("select public.plus_is_current(%s)", b.user_id)[0][0])
        self.assertTrue(b.rpc("super_allowance")["unlimited"])
        # A refund ends it for every account holding the purchase.
        admin("select public.record_verified_plus(%s,%s,false)", a.user_id, original)
        self.assertFalse(d.rpc("super_allowance")["unlimited"])
        self.assertFalse(b.rpc("super_allowance")["unlimited"])
        self.assertFalse(a.rpc("super_allowance")["unlimited"])
        with self.fails("super_daily_limit", 409): a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
        admin("select public.record_verified_plus(%s,%s,true)", a.user_id, original)
        admin("update private.plus_entitlements set valid_until=now()-interval '1 minute' where user_id=%s", a.user_id)
        with self.fails("super_daily_limit", 409): a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")

    def test_your_word_needs_plus_and_reaches_only_plain_pssts(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        pair = connect(ada, emre)
        service = Api("service_role")
        with self.fails("plus_required", 403):
            ada.rpc("set_psst_word", "boop")
        with self.fails("invalid_word", 422):
            ada.rpc("set_psst_word", "anything I like")
        with self.fails("invalid_word", 422):
            ada.rpc("set_psst_word", "pışt")
        admin("select public.record_verified_plus(%s,%s,true)", ada.user_id, str(uuid.uuid4()))
        ada.rpc("set_psst_word", "boop")
        self.assertEqual(ada.rpc("my_psst_word"), "boop")
        event = uuid.uuid4()
        ada.rpc("send_signal", event, pair, "psst")
        self.assertEqual(service.rpc("push_targets", event)["word"], "boop")
        self.assertEqual(emre.rows("select word from public.list_unseen()")[0][0], "boop")
        superevent = uuid.uuid4()
        ada.rpc("send_signal", superevent, pair, "super_psst")
        self.assertIsNone(service.rpc("push_targets", superevent)["word"], "Super Psst keeps its own wording")
        # When Psst+ lapses the word stops showing; "psst" clears it.
        admin("update private.plus_entitlements set valid_until=now()-interval '1 minute' where user_id=%s", ada.user_id)
        self.assertIsNone(service.rpc("push_targets", event)["word"])
        ada.rpc("set_psst_word", "psst")
        self.assertIsNone(ada.rpc("my_psst_word"))

    def test_connected_people_see_only_each_others_name(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        connect(ada, emre)
        self.assertEqual(sorted(r[0] for r in ada.rows("select display_name from public.profiles")), ["Ada", "Emre"])
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("select notification_sound from public.profiles")

    def test_app_versions_are_reported_privately_and_requirements_are_public(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        connect(ada, emre)
        ada.rpc("report_app_version", "1.0.4", 24)
        self.assertEqual(admin("select app_version, app_build from public.profiles where id = %s", ada.user_id),
                         [("1.0.4", 24)])
        with self.assertRaises(errors.InsufficientPrivilege):
            emre.rows("select app_version from public.profiles")
        with self.fails("invalid_version", 422):
            ada.rpc("report_app_version", "x" * 30, 1)
        self.assertEqual(Api("anon").rpc("app_requirements")["min_build"], 0)
        admin("update public.app_config set min_build = 24, latest_build = 25, latest_version = '1.0.5'")
        self.assertEqual(ada.rpc("app_requirements"), {"min_build": 24, "latest_build": 25, "latest_version": "1.0.5"})
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("update public.app_config set min_build = 0")
        admin("update public.app_config set min_build = 0, latest_build = 0, latest_version = null")

    def test_recipient_can_mute_super_without_changing_sender_event(self):
        a, b = new_user("A"), new_user("B")
        pair = connect(a, b)
        b.rpc("set_super_effects", False)
        event = uuid.uuid4()
        a.rpc("send_signal", event, pair, "super_psst")
        targets = admin("select public.push_targets(%s)", event)[0][0]
        self.assertEqual(targets["effect_id"], "psst")
        self.assertEqual(targets["sound"], "psst.wav")
        self.assertEqual(b.rows("select effect_id from public.list_unseen()"), [("psst",)])
        b.rpc("set_super_effects", True)
        targets = admin("select public.push_targets(%s)", event)[0][0]
        self.assertEqual(targets["effect_id"], "super_psst")
        self.assertEqual(targets["sound"], "psst-super.wav")

    def test_activity_is_private_counts_both_directions_and_excludes_old_events(self):
        a, b, stranger = new_user("A"), new_user("B"), new_user("Stranger")
        pair = connect(a, b)
        a.rpc("send_signal", uuid.uuid4(), pair, "psst")
        b.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
        old = uuid.uuid4(); a.rpc("send_signal", old, pair, "psst")
        admin("update public.signal_events set created_at=now()-interval '31 days' where id=%s", old)
        self.assertEqual(a.rows("select other_name,sent_count,received_count from public.personal_activity()"), [("B",1,1)])
        self.assertEqual(b.rows("select other_name,sent_count,received_count from public.personal_activity()"), [("A",1,1)])
        self.assertEqual(stranger.rows("select * from public.personal_activity()"), [])
        with self.assertRaises(errors.InsufficientPrivilege): Api("anon").rpc("personal_activity")
        a.rpc("block_user", b.user_id)
        self.assertEqual(a.rows("select * from public.personal_activity()"), [])

    def test_all_time_activity_survives_the_purge_and_counts_each_psst_once(self):
        a, b, stranger = new_user("A"), new_user("B"), new_user("Stranger")
        pair = connect(a, b)
        first = uuid.uuid4()
        a.rpc("send_signal", first, pair, "psst")
        a.rpc("send_signal", first, pair, "psst")  # retry: same event, counted once
        old = uuid.uuid4()
        a.rpc("send_signal", old, pair, "psst")
        b.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
        admin("update public.signal_events set created_at=now()-interval '40 days' where id=%s", old)
        admin("select private.purge_expired()")
        month = "now() - interval '20 days'"
        rows = a.rows(f"select other_name,sent_all,received_all,sent_month,received_month from public.personal_activity_all({month})")
        self.assertEqual(rows, [("B", 2, 1, 1, 1)])
        self.assertEqual(b.rows(f"select sent_all,received_all from public.personal_activity_all({month})"), [(1, 2)])
        self.assertEqual(stranger.rows(f"select * from public.personal_activity_all({month})"), [])
        with self.assertRaises(errors.InsufficientPrivilege):
            a.rows("select * from private.pair_counts")
        with self.assertRaises(errors.InsufficientPrivilege):
            Api("anon").rpc("personal_activity_all", None)
        a.rpc("remove_connection", pair)
        self.assertEqual(admin("select count(*) from private.pair_counts where connection_id = %s", pair)[0][0], 0)

    # Streak saver (5A), quiet week (11A), link reminder kind (13A) --------------

    def _day_psst(self, conn, sender, recipient, day, hour=12):
        """A Psst at noon UTC on a given date (the test people keep UTC time)."""
        import datetime
        at = datetime.datetime.combine(day, datetime.time(hour), datetime.timezone.utc)
        admin("insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, created_at) "
              "values (gen_random_uuid(), %s, %s, %s, 'psst', %s)", conn, sender.user_id, recipient.user_id, at)

    def _keep(self, conn, a, b, *days):
        for day in days:
            self._day_psst(conn, a, b, day)
            self._day_psst(conn, b, a, day)

    @staticmethod
    def _streak_on(conn, day):
        return admin("select private.streak_days_on(%s, %s)", conn, day)[0][0]

    @staticmethod
    def _freezes(conn):
        return admin("select day, user_id, plus from private.streak_freezes where connection_id = %s order by day", conn)

    def test_streak_saver_switch_and_status(self):
        ada = new_user("Ada")
        ada.rpc("set_time_zone", "UTC")
        self.assertEqual(ada.rpc("streak_saver_status"), {"enabled": False, "unlimited": False, "freezes_left": 1},
                         "off by default (the 3A rule stays the default)")
        ada.rpc("set_streak_reminders", True)
        self.assertTrue(ada.rpc("streak_saver_status")["enabled"])
        with self.fails("invalid_preference", 422):
            ada.rpc("set_streak_reminders", None)
        self.assertTrue(ada.rpc("streak_saver_status")["enabled"], "a refused call changes nothing")

        # This month's free freeze spent: none left; last month's doesn't count.
        emre = new_user("Emre")
        pair = connect(ada, emre)
        admin("insert into private.streak_freezes (connection_id, day, user_id, plus) "
              "values (%s, (date_trunc('month', now() at time zone 'UTC') - interval '1 day')::date, %s, false)",
              pair, ada.user_id)
        self.assertEqual(ada.rpc("streak_saver_status")["freezes_left"], 1)
        admin("insert into private.streak_freezes (connection_id, day, user_id, plus) "
              "values (%s, (now() at time zone 'UTC')::date, %s, false)", pair, ada.user_id)
        self.assertEqual(ada.rpc("streak_saver_status"), {"enabled": True, "unlimited": False, "freezes_left": 0})
        self.assertEqual(emre.rpc("streak_saver_status")["freezes_left"], 1, "spent from one account only")

        admin("insert into private.plus_entitlements (user_id, original_transaction_id, valid_until) "
              "values (%s, %s, now() + interval '30 days')", ada.user_id, "streak-plus-" + uuid.uuid4().hex)
        self.assertEqual(ada.rpc("streak_saver_status"), {"enabled": True, "unlimited": True, "freezes_left": 1})
        ada.rpc("set_streak_reminders", False)
        self.assertFalse(ada.rpc("streak_saver_status")["enabled"])

        ghost = Api("authenticated", uuid.uuid4())
        with self.fails("profile_required", 409):
            ghost.rpc("set_streak_reminders", True)
        for fn in ("streak_saver_status", "set_streak_reminders"):
            with self.assertRaises(errors.InsufficientPrivilege):
                Api("anon").rpc(fn, *((True,) if fn == "set_streak_reminders" else ()))
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("streak_reminder_targets")
        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rows("select * from private.streak_freezes")

    def test_streak_freeze_forgives_one_missed_day_a_month(self):
        import datetime
        D = lambda d: datetime.date(2026, 10, d)
        ada, emre = new_user("Ada"), new_user("Emre")
        for person in (ada, emre):
            person.rpc("set_time_zone", "UTC")
        ada.rpc("set_streak_reminders", True)   # Emre hasn't turned it on
        pair = connect(ada, emre)

        self._keep(pair, ada, emre, D(1), D(2), D(3))
        # Oct 4 missed. On Oct 5 the streak is still alive: a freeze is ready.
        self.assertEqual(self._streak_on(pair, D(5)), 3)
        self.assertEqual(self._streak_on(pair, D(6)), 0, "two missed days end it")
        self._keep(pair, ada, emre, D(5))
        self.assertEqual(self._streak_on(pair, D(5)), 4, "goes on across the frozen day (which doesn't add)")
        self.assertEqual(self._freezes(pair), [(D(4), ada.user_id, False)], "spent from Ada's account")

        # A second miss in October: Ada's free freeze is gone and Emre has no saver.
        self._keep(pair, ada, emre, D(6))
        self.assertEqual(self._streak_on(pair, D(8)), 0)
        self._keep(pair, ada, emre, D(8))
        self.assertEqual(self._streak_on(pair, D(8)), 1, "starts again")
        self.assertEqual(len(self._freezes(pair)), 1)

        # With Emre's saver on too, his freeze saves the next miss: either person's works.
        emre.rpc("set_streak_reminders", True)
        self._keep(pair, ada, emre, D(9))
        self.assertEqual(self._streak_on(pair, D(11)), 2)
        self._keep(pair, ada, emre, D(11))
        self.assertEqual(self._streak_on(pair, D(11)), 3)
        self.assertEqual(self._freezes(pair)[-1], (D(10), emre.user_id, False))

        # A new month brings a new free freeze.
        self._keep(pair, ada, emre, D(31))           # breaks (Oct 12–30 missed), streak 1
        self._keep(pair, ada, emre, datetime.date(2026, 11, 2))
        self.assertEqual(self._streak_on(pair, datetime.date(2026, 11, 2)), 2)
        self.assertEqual(self._freezes(pair)[-1][0], datetime.date(2026, 11, 1))

        # Turning the saver off: no freeze is ready any more.
        ada.rpc("set_streak_reminders", False); emre.rpc("set_streak_reminders", False)
        self.assertEqual(self._streak_on(pair, datetime.date(2026, 11, 4)), 0)

    def test_streak_without_saver_is_unchanged_and_plus_is_unlimited(self):
        import datetime
        D = lambda d: datetime.date(2026, 10, d)
        kim, sam, mia, leo = new_user("Kim"), new_user("Sam"), new_user("Mia"), new_user("Leo")
        for person in (kim, sam, mia, leo):
            person.rpc("set_time_zone", "UTC")

        plain = connect(kim, sam)
        self._keep(plain, kim, sam, D(1), D(2), D(3))
        self.assertEqual(self._streak_on(plain, D(5)), 0, "no saver: a missed day ends it, as before")
        self._keep(plain, kim, sam, D(5))
        self.assertEqual(self._streak_on(plain, D(5)), 1)
        self.assertEqual(self._freezes(plain), [])

        # Psst+ with the saver on: every single missed day is forgiven.
        admin("insert into private.plus_entitlements (user_id, original_transaction_id, valid_until) "
              "values (%s, %s, now() + interval '30 days')", mia.user_id, "streak-plus-" + uuid.uuid4().hex)
        mia.rpc("set_streak_reminders", True)
        plus = connect(mia, leo)
        self._keep(plus, mia, leo, D(1), D(3), D(5), D(7))
        self.assertEqual(self._streak_on(plus, D(7)), 4)
        self.assertEqual([f[2] for f in self._freezes(plus)], [True, True, True], "Psst+ freezes don't use the monthly one")
        self.assertEqual(mia.rpc("streak_saver_status")["unlimited"], True)
        self._keep(plus, mia, leo, D(10))
        self.assertEqual(self._streak_on(plus, D(10)), 1, "two missed days in a row end it even with Psst+")

        # Psst+ without the saver switched on: unaffected.
        admin("update public.profiles set streak_reminders = false where id = %s", mia.user_id)
        self.assertEqual(self._streak_on(plus, D(12)), 0)

    def test_streak_days_shows_a_frozen_streak_everywhere(self):
        import datetime
        today = datetime.datetime.now(datetime.timezone.utc).date()
        ada, emre, sam, kim = new_user("Ada"), new_user("Emre"), new_user("Sam"), new_user("Kim")
        for person in (ada, emre, sam, kim):
            person.rpc("set_time_zone", "UTC")
        ada.rpc("set_streak_reminders", True)
        saved, plain = connect(ada, emre), connect(sam, kim)
        days = [today - datetime.timedelta(days=n) for n in (4, 3, 2)]   # yesterday missed
        self._keep(saved, ada, emre, *days)
        self._keep(plain, sam, kim, *days)

        def listed(viewer, conn):
            return viewer.rows("select streak_days from public.list_connections() where connection_id = %s", conn)[0][0]

        self.assertEqual((listed(ada, saved), listed(emre, saved)), (3, 3), "Ada's freeze keeps it alive for both")
        self.assertEqual(listed(sam, plain), 0)
        recap = admin("select private.recap_for(%s, %s)", emre.user_id, today)[0][0]
        self.assertEqual(recap["streak"]["days"], 3, "the recap agrees")
        token = secrets.token_hex(24)
        emre.rpc("register_widget_token", token)
        people = {p["connection_id"]: p["streak_days"] for p in Api("anon").rpc("widget_state", token)["people"]}
        self.assertEqual(people[str(saved)], 3, "and the widget")

    def test_streak_reminder_at_8pm_once_a_day_for_the_longest_streak_at_risk(self):
        import datetime
        D = lambda d: datetime.date(2026, 10, d)
        at = lambda d, h: datetime.datetime(2026, 10, d, h, 30, tzinfo=datetime.timezone.utc)
        ada, emre, mia, kim = new_user("Ada"), new_user("Emre"), new_user("Mia"), new_user("Kim")
        for person in (ada, emre, mia, kim):
            person.rpc("set_time_zone", "UTC")
        ada.rpc("register_device_token", "5a" * 32, "sandbox")
        admin("update public.profiles set notification_sound = 'psst-soft.wav' where id = %s", ada.user_id)
        with_emre, with_mia, with_kim = connect(ada, emre), connect(ada, mia), connect(ada, kim)

        def targets(now):
            return admin("select private.streak_reminder_targets_at(%s)", now)[0][0]

        self._keep(with_emre, ada, emre, D(7), D(8), D(9))            # 3 days
        self._keep(with_mia, ada, mia, D(4), D(5), D(6), D(7), D(8), D(9))  # 6 days
        self._keep(with_kim, ada, kim, D(8), D(9))                    # 2: too short to remind
        self.assertEqual(targets(at(10, 20)), [], "off by default: nobody gets one")

        ada.rpc("set_streak_reminders", True)
        self.assertEqual(targets(at(10, 20)), [], "a free freeze would save it: 'ends at midnight' isn't true")
        # Ada's October freeze is spent (and nobody else has the saver).
        admin("insert into private.streak_freezes (connection_id, day, user_id, plus) values (%s, %s, %s, false)",
              with_kim, D(1), ada.user_id)
        self.assertEqual(targets(at(10, 19)), [], "not before 8 PM")
        sent = targets(at(10, 20))
        self.assertEqual(sent, [{
            "user_id": str(ada.user_id), "connection_id": str(with_mia),
            "body": "Your 6-day streak with Mia ends at midnight 🔥", "sound": "psst-soft.wav",
            "tokens": [{"token": "5a" * 32, "environment": "sandbox"}]}], "one push, the longest streak")
        self.assertEqual(targets(at(10, 21)), [], "never more than one a day")
        self.assertEqual(targets(at(10, 23)), [])

        # Next day: Mia's streak is kept today, Emre's isn't; Emre's goes out.
        self._keep(with_emre, ada, emre, D(10)); self._keep(with_mia, ada, mia, D(10))
        self._keep(with_mia, ada, mia, D(11))
        self.assertEqual([t["body"] for t in targets(at(11, 20))], ["Your 4-day streak with Emre ends at midnight 🔥"])

        # Everything kept today: nothing to say.
        self._keep(with_emre, ada, emre, D(12)); self._keep(with_mia, ada, mia, D(12))
        self.assertEqual(targets(at(12, 22)), [])
        # A streak already broken isn't at risk.
        self.assertEqual(targets(at(14, 20)), [])

        # Emre never turned it on: he gets nothing, whatever his streaks.
        self.assertNotIn(str(emre.user_id), {t["user_id"] for t in targets(at(13, 20))})

        # Two runs at once: still one.
        self._keep(with_mia, ada, mia, D(13))
        admin("delete from private.streak_reminder_state where user_id = %s", ada.user_id)
        with ThreadPoolExecutor(4) as pool:
            runs = list(pool.map(lambda _: targets(at(14, 20)), range(4)))
        self.assertEqual(sum(len(r) for r in runs), 1)

        self.assertEqual(Api("service_role").rpc("streak_reminder_targets").__class__, list)

    def test_quiet_week_push_after_a_quiet_week_at_most_every_three_weeks(self):
        import datetime
        D = lambda m, d: datetime.date(2026, m, d)
        sunday_at = lambda m, d, h: datetime.datetime(2026, m, d, h, 30, tzinfo=datetime.timezone.utc)
        ada, kim, sam = new_user("Ada"), new_user("Kim"), new_user("Sam")
        for person in (ada, kim, sam):
            person.rpc("set_time_zone", "UTC")
        kim.rpc("set_weekly_recap", False)
        sam.rpc("set_weekly_recap", False)
        ada.rpc("register_device_token", "9e" * 32, "production")
        with_kim, with_sam = connect(ada, kim), connect(ada, sam)

        def targets(now):
            return [t for t in admin("select private.quiet_week_targets_at(%s)", now)[0][0]
                    if t["user_id"] == str(ada.user_id)]

        # Week of Oct 12–18: Kim 3, Sam 1. Week of Oct 19–25: nothing.
        for _ in range(3):
            self._day_psst(with_kim, kim, ada, D(10, 14))
        self._day_psst(with_sam, ada, sam, D(10, 15))
        self.assertEqual(targets(sunday_at(10, 18, 20)), [], "that week had Pssts")
        self.assertEqual(targets(sunday_at(10, 25, 17)), [], "not before 6 PM")
        self.assertEqual(targets(sunday_at(10, 25, 18)), [{
            "user_id": str(ada.user_id), "connection_id": str(with_kim), "body": "Quiet week. Psst Kim?",
            "sound": "psst.wav", "tokens": [{"token": "9e" * 32, "environment": "production"}]}])
        self.assertEqual(targets(sunday_at(10, 25, 19)), [], "once")
        self.assertEqual(targets(sunday_at(11, 1, 18)), [], "the week before was quiet too")

        # Busy again Oct 26–Nov 1, quiet Nov 2–8: within three weeks of the last one.
        self._day_psst(with_sam, sam, ada, D(10, 28))
        admin("update private.quiet_week_state set last_checked = %s where user_id = %s", D(10, 25), ada.user_id)
        self.assertEqual(targets(sunday_at(11, 8, 18)), [], "at most once every three weeks")
        # Three weeks on, it may send again (Sam was #1 the week before).
        admin("update private.quiet_week_state set last_sent = %s, last_checked = %s where user_id = %s",
              D(10, 18), D(10, 25), ada.user_id)
        self.assertEqual([t["body"] for t in targets(sunday_at(11, 8, 18))], ["Quiet week. Psst Sam?"])

        # Blocked, removed, or recap switched off: nothing.
        reset = lambda: admin("update private.quiet_week_state set last_sent = null, last_checked = null where user_id = %s",
                              ada.user_id)
        reset()
        admin("insert into public.blocks (blocker_id, blocked_id) values (%s, %s)", sam.user_id, ada.user_id)
        self.assertEqual(targets(sunday_at(11, 8, 18)), [], "skipped if they blocked each other")
        admin("delete from public.blocks where blocker_id = %s", sam.user_id)
        reset()
        ada.rpc("set_weekly_recap", False)
        self.assertEqual(targets(sunday_at(11, 8, 18)), [], "the recap switch turns it off")
        ada.rpc("set_weekly_recap", True)
        reset()
        admin("delete from public.connections where id = %s", with_sam)
        self.assertEqual(targets(sunday_at(11, 8, 18)), [], "no longer connected")

        with self.assertRaises(errors.InsufficientPrivilege):
            ada.rpc("quiet_week_targets")
        self.assertIsInstance(Api("service_role").rpc("quiet_week_targets"), list)

    def test_link_reminder_says_which_link_it_is(self):
        ada = new_user("Ada")
        admin("update public.profiles set app_build = 40 where id = %s", ada.user_id)
        plain = ada.rpc("create_psst_invite")["code"]
        doodle = ada.rpc("create_psst_invite", json.dumps([[[0.2, 0.3], [0.5, 0.8]]]))["code"]
        admin("update public.invites set created_at = now() - interval '5 days' where code in (%s, %s)", plain, doodle)
        kinds = {t["code"]: t["kind"] for t in Api("service_role").rpc("invite_reminder_targets")
                 if t["user_id"] == str(ada.user_id)}
        self.assertEqual(kinds, {plain: "psst", doodle: "doodle"})

if __name__ == "__main__":
    unittest.main(verbosity=1)
