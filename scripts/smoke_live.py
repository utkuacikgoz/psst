#!/usr/bin/env python3
"""End-to-end check of a deployed Psst backend, run after each deploy.

Creates three throwaway anonymous accounts, exercises invites, sending,
idempotent retry, authorization refusal and acknowledgement, then deletes
all three accounts. Needs SUPABASE_PROJECT_REF and SUPABASE_ANON_KEY.
It never touches real users and sends no push (the test accounts have no
device tokens), so it can't disturb anyone.
"""
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

REF = os.environ["SUPABASE_PROJECT_REF"]
ANON = os.environ["SUPABASE_ANON_KEY"]
BASE = f"https://{REF}.supabase.co"
failures = []


def call(path, body, token=None):
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), method="POST", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, raw.decode(errors="replace")


def check(name, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + name + ("" if condition else f"  ({detail})"))
    if not condition:
        failures.append(name)


class User:
    def __init__(self, name):
        status, body = call("/auth/v1/signup", {"data": {}})
        if status != 200:
            sys.exit(f"Anonymous sign-up failed ({status}): {body}. Is 'Allow anonymous sign-ins' on?")
        self.token = body["access_token"]
        self.id = body["user"]["id"]
        status, body = self.rpc("set_display_name", p_name=name)
        check(f"{name} sets a display name", status in (200, 204), body)

    def rpc(self, fn, **params):
        return call(f"/rest/v1/rpc/{fn}", params, self.token)

    def send(self, event_id, connection_id, effect):
        return call("/functions/v1/send-signal",
                    {"event_id": event_id, "connection_id": connection_id, "effect_id": effect}, self.token)

    def delete(self):
        return call("/functions/v1/delete-account", {}, self.token)


users = []
try:
    status, body = call("/functions/v1/send-signal", {})
    check("send-signal rejects a request without a user token", status == 401, f"{status} {body}")

    ada, emre, sam = User("Smoke Ada"), User("Smoke Emre"), User("Smoke Sam")
    users = [ada, emre, sam]

    status, body = ada.rpc("create_invite")
    code = body.get("code") if isinstance(body, dict) else None
    check("Ada creates an invite", status == 200 and code, body)

    status, body = emre.rpc("preview_invite", p_code=code)
    check("Emre sees Ada's pending invite", body == {"status": "pending", "inviter_name": "Smoke Ada"}, body)

    status, body = emre.rpc("accept_invite", p_code=code)
    connection = body.get("connection_id") if isinstance(body, dict) else None
    check("Emre accepts; the connection exists", status == 200 and connection, body)

    status, body = sam.rpc("preview_invite", p_code=code)
    check("Sam sees the used invite as used", isinstance(body, dict) and body.get("status") == "used", body)

    event = str(uuid.uuid4())
    status, body = ada.send(event, connection, "psst")
    check("Ada's signal is accepted by the server", status == 200 and body.get("duplicate") is False, body)
    check("No device registered is reported, not delivery",
          isinstance(body, dict) and body.get("push_status") == "no_devices", body)

    status, body = ada.send(event, connection, "psst")
    check("Retrying the same event ID is a duplicate, not a new signal",
          status == 200 and body.get("duplicate") is True, body)

    status, body = ada.send(str(uuid.uuid4()), connection, "duck")
    check("A removed signal (Duck) is refused",
          status == 403 and isinstance(body, dict) and body.get("error") == "effect_unavailable", f"{status} {body}")

    status, body = sam.send(str(uuid.uuid4()), connection, "psst")
    check("Sam cannot send on Ada and Emre's connection",
          status == 403 and isinstance(body, dict) and body.get("error") == "not_connected", f"{status} {body}")

    status, body = sam.rpc("list_connections")
    check("Sam cannot see their connection", status == 200 and body == [], body)

    status, body = emre.rpc("list_unseen")
    check("Emre has exactly one unseen signal from Ada",
          status == 200 and len(body) == 1 and body[0]["sender_name"] == "Smoke Ada", body)

    status, body = ada.rpc("ack_signals", p_event_ids=[event])
    check("Ada cannot mark her own signal seen", body == 0, body)
    status, body = emre.rpc("ack_signals", p_event_ids=[event])
    check("Emre marks it seen", body == 1, body)

    status, body = ada.rpc("list_connections")
    check("Ada now sees it as seen",
          status == 200 and len(body) == 1 and body[0]["last_seen_at"] is not None, body)
finally:
    for user in users:
        status, body = user.delete()
        check("Deletes a test account", status == 204, f"{status} {body}")

print()
if failures:
    sys.exit(f"{len(failures)} check(s) failed.")
print("All live checks passed.")
