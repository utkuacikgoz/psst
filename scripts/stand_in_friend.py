#!/usr/bin/env python3
"""A stand-in friend for recording the app alone (e.g. for App Review).

A real anonymous account on the chosen backend accepts your invite code, then:
- 30 seconds after connecting, it sends you one Psst (to show a notification
  and "Psst back");
- whenever you psst it, it marks your Psst seen and pssts back: the first time
  after 15 seconds (an ordinary arrival), later times after 4 seconds (inside
  the 10-second window, so both phones show SAME MOMENT once a minute at most).
When the time is up it deletes its account, so its band disappears.
Needs SUPABASE_PROJECT_REF, SUPABASE_ANON_KEY, INVITE_CODE; optional
FRIEND_NAME and MINUTES.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE = f"https://{os.environ['SUPABASE_PROJECT_REF']}.supabase.co"
ANON = os.environ["SUPABASE_ANON_KEY"]

CODE = os.environ["INVITE_CODE"].strip().upper()
NAME = os.environ.get("FRIEND_NAME") or "Zoe"
MINUTES = int(os.environ.get("MINUTES") or 10)


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
        return error.code, error.read().decode(errors="replace")


def rpc(token, fn, **params):
    return call(f"/rest/v1/rpc/{fn}", params, token)


def send(token, connection):
    status, body = call("/functions/v1/send-signal",
                        {"event_id": str(uuid.uuid4()), "connection_id": connection, "effect_id": "psst"}, token)
    print(f"  sent a Psst: {status} {body}", flush=True)


status, body = call("/auth/v1/signup", {"data": {}})
if status != 200:
    sys.exit(f"Sign-up failed ({status}): {body}")
token = body["access_token"]
try:
    rpc(token, "set_display_name", p_name=NAME)
    status, body = rpc(token, "accept_invite", p_code=CODE)
    connection = body.get("connection_id") if isinstance(body, dict) else None
    if not connection:
        sys.exit(f"Couldn't accept {CODE} ({status}): {body}. Make a new code in the app and run again.")
    print(f"{NAME} connected. Staying for {MINUTES} minutes.", flush=True)

    deadline = time.time() + MINUTES * 60
    opener_at = time.time() + 30
    replies = 0
    while time.time() < deadline:
        if opener_at and time.time() >= opener_at:
            print("Opening Psst:", flush=True)
            send(token, connection)
            opener_at = None
        status, unseen = rpc(token, "list_unseen")
        mine = [s for s in unseen or [] if s["connection_id"] == connection] if status == 200 else []
        if mine:
            rpc(token, "ack_signals", p_event_ids=[s["id"] for s in mine])
            print(f"Got {len(mine)} Psst(s), marked seen.", flush=True)
            time.sleep(15 if replies == 0 else 4)
            send(token, connection)
            replies += 1
        time.sleep(2)
finally:
    status, _ = call("/functions/v1/delete-account", {}, token)
    print(f"{NAME}'s account deleted ({status}).")
