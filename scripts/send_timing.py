#!/usr/bin/env python3
"""Times a Psst send on the chosen backend, end to end, the way the app does it.

Two temporary anonymous accounts connect with an invite. The recipient gets a
made-up device token, so every send also makes a real round trip to Apple's
push service (Apple rejects the token, as it would an expired one). Then:
- send-signal, as the app calls it (stores the Psst, then hands the push to Apple);
- send_signal straight to the database, which only stores it (no push);
Both accounts are deleted at the end. Needs SUPABASE_PROJECT_REF, SUPABASE_ANON_KEY.
"""
import json
import os
import secrets
import statistics
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE = f"https://{os.environ['SUPABASE_PROJECT_REF']}.supabase.co"
ANON = os.environ["SUPABASE_ANON_KEY"]


def call(path, body, token=None):
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), method="POST", headers=headers)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None), (time.monotonic() - started) * 1000
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace"), (time.monotonic() - started) * 1000


def account(name):
    status, body, _ = call("/auth/v1/signup", {"data": {}})
    if status != 200:
        sys.exit(f"Sign-up failed ({status}): {body}")
    token = body["access_token"]
    call("/rest/v1/rpc/set_display_name", {"p_name": name}, token)
    return token


def summary(label, times):
    times = sorted(times)
    print(f"{label}: median {statistics.median(times):.0f} ms · fastest {times[0]:.0f} ms · slowest {times[-1]:.0f} ms "
          f"({len(times)} sends)", flush=True)


sender = account("Timing A")
recipient = account("Timing B")
try:
    _, invite, _ = call("/rest/v1/rpc/create_invite", {}, sender)
    _, accepted, _ = call("/rest/v1/rpc/accept_invite", {"p_code": invite["code"]}, recipient)
    connection = accepted["connection_id"]
    status, body, _ = call("/rest/v1/rpc/register_device_token",
                           {"p_token": secrets.token_hex(32), "p_environment": "production"}, recipient)
    print(f"Connected; recipient device registered ({status}).", flush=True)

    full = []
    for i in range(5):
        status, body, ms = call("/functions/v1/send-signal",
                                {"event_id": str(uuid.uuid4()), "connection_id": connection, "effect_id": "psst"}, sender)
        print(f"  send-signal #{i + 1}: {status} in {ms:.0f} ms (push: {body.get('push_status') if isinstance(body, dict) else body})",
              flush=True)
        if status == 200:
            full.append(ms)
        # Apple dropped the made-up token after the first send; give it a new one each time.
        call("/rest/v1/rpc/register_device_token", {"p_token": secrets.token_hex(32), "p_environment": "production"}, recipient)
        time.sleep(2)

    store_only = []
    for i in range(4):
        status, body, ms = call("/rest/v1/rpc/send_signal",
                                {"p_event_id": str(uuid.uuid4()), "p_connection_id": connection, "p_effect_id": "psst"}, sender)
        print(f"  store only #{i + 1}: {status} in {ms:.0f} ms", flush=True)
        if status == 200:
            store_only.append(ms)
        time.sleep(2)

    print()
    if full:
        summary("What the app waits for today (store + push to Apple)", full)
    if store_only:
        summary("Storing the Psst alone", store_only)
finally:
    for token in (sender, recipient):
        call("/functions/v1/delete-account", {}, token)
    print("Both temporary accounts deleted.", flush=True)
