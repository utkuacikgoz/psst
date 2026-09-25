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

    def test_only_inviter_can_revoke(self):
        ada, sam = new_user("Ada"), new_user("Sam")
        code = ada.rpc("create_invite")["code"]
        with self.fails("invite_invalid", 404):
            sam.rpc("revoke_invite", code)

    def test_invite_limit(self):
        ada = new_user("Ada")
        for _ in range(5):
            ada.rpc("create_invite")
        with self.fails("too_many_invites", 429):
            ada.rpc("create_invite")

    def test_invites_need_a_profile(self):
        user_id = admin("insert into auth.users default values returning id")[0][0]
        with self.fails("profile_required", 409):
            Api("authenticated", user_id).rpc("create_invite")

    # Sending ---------------------------------------------------------------

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


if __name__ == "__main__":
    unittest.main(verbosity=1)
