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
        placeholders = ", ".join(["%s"] * len(args))
        with self._cursor() as cur:
            cur.execute(f"select public.{fn}({placeholders})", args)
            return cur.fetchone()[0]

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


class ErrorCode:
    """Asserts a PostgREST-style error: SQLSTATE PTxxx with a message."""

    def __init__(self, test, message, status):
        self.test, self.message, self.status = test, message, status

    def __enter__(self):
        return self

    def __exit__(self, kind, value, tb):
        self.test.assertIsNotNone(value, f"expected {self.message}")
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

    def test_invite_accept_creates_mutual_connection(self):
        ada, emre = new_user("Ada"), new_user("Emre")
        code = ada.rpc("create_invite")["code"]
        self.assertEqual(len(code), 8)
        preview = emre.rpc("preview_invite", code.lower()[:4] + "-" + code.lower()[4:])
        self.assertEqual(preview, {"status": "pending", "inviter_name": "Ada"})
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
        self.assertEqual(sam.rpc("preview_invite", used), {"status": "used", "inviter_name": None})
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
            except psycopg.Error as error:
                return error.diag.message_primary

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
        self.assertEqual(emre.rpc("preview_invite", code), {"status": "invalid", "inviter_name": None})
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
            except psycopg.Error as error:
                return error.diag.message_primary
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
        # Restoring on a new account moves the purchase there.
        admin("select public.record_verified_plus(%s,%s,true)", b.user_id, original)
        self.assertTrue(b.rpc("super_allowance")["unlimited"])
        self.assertFalse(a.rpc("super_allowance")["unlimited"])
        with self.assertRaises(errors.InsufficientPrivilege):
            a.rpc("plus_is_current", a.user_id)
        self.assertTrue(admin("select public.plus_is_current(%s)", b.user_id)[0][0])
        admin("select public.record_verified_plus(%s,%s,false)", a.user_id, original)
        self.assertFalse(b.rpc("super_allowance")["unlimited"])
        self.assertFalse(a.rpc("super_allowance")["unlimited"])
        with self.fails("super_daily_limit", 409): a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")
        admin("select public.record_verified_plus(%s,%s,true)", a.user_id, original)
        admin("update private.plus_entitlements set valid_until=now()-interval '1 minute' where user_id=%s", a.user_id)
        with self.fails("super_daily_limit", 409): a.rpc("send_signal", uuid.uuid4(), pair, "super_psst")

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


if __name__ == "__main__":
    unittest.main(verbosity=1)
