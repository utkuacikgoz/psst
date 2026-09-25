import { assertEquals } from "jsr:@std/assert@1";
import { buildPayload, deliver, DeliverDeps, PushStatus, PushTargets } from "../_shared/deliver.ts";
import { ApnsResult } from "../_shared/apns.ts";

const EVENT = "11111111-1111-4111-8111-111111111111";

function targets(overrides: Partial<PushTargets> = {}): PushTargets {
  return {
    event_id: EVENT,
    connection_id: "22222222-2222-4222-8222-222222222222",
    effect_id: "psst",
    push_status: "pending",
    sender_name: "Ada",
    tokens: [{ token: "t1", environment: "sandbox" }, { token: "t2", environment: "production" }],
    ...overrides,
  };
}

function fakeDeps(t: PushTargets | null, results: Record<string, ApnsResult | Error>) {
  const recorded: { status: PushStatus; invalid: string[] }[] = [];
  const sent: string[] = [];
  const deps: DeliverDeps = {
    pushTargets: () => Promise.resolve(t),
    recordPushResult: (_id, status, invalid) => {
      recorded.push({ status, invalid });
      return Promise.resolve();
    },
    sendPush: (token) => {
      sent.push(token);
      const r = results[token];
      return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
    },
    nowSeconds: () => 1000,
  };
  return { deps, recorded, sent };
}

Deno.test("payload names the sender first and carries routing data", () => {
  const payload = buildPayload(targets());
  assertEquals(payload.aps.alert, { title: "Ada", body: "Psst" });
  assertEquals(payload.aps.category, "SIGNAL");
  assertEquals(payload.aps.sound, "psst.wav"); // bundled in the app
  assertEquals(payload.psst.event_id, EVENT);
  assertEquals(payload.psst.effect_id, "psst");
  assertEquals(payload.psst.same_moment, false);
  assertEquals(buildPayload(targets({ same_moment: true })).psst.same_moment, true);
  // Well under APNs' 4 KB limit even with a 40-character name.
  const size = new TextEncoder().encode(JSON.stringify(buildPayload(targets({ sender_name: "x".repeat(40) })))).length;
  assertEquals(size < 1024, true);
});

Deno.test("accepted by one device is accepted; dead tokens are removed", async () => {
  const { deps, recorded } = fakeDeps(targets(), {
    t1: { status: 200 },
    t2: { status: 410, reason: "Unregistered" },
  });
  assertEquals(await deliver(EVENT, deps), "accepted");
  assertEquals(recorded, [{ status: "accepted", invalid: ["t2"] }]);
});

Deno.test("all tokens dead means no devices", async () => {
  const { deps, recorded } = fakeDeps(targets(), {
    t1: { status: 400, reason: "BadDeviceToken" },
    t2: { status: 410 },
  });
  assertEquals(await deliver(EVENT, deps), "no_devices");
  assertEquals(recorded, [{ status: "no_devices", invalid: ["t1", "t2"] }]);
});

Deno.test("network errors and throttling are failures, and tokens are kept", async () => {
  const { deps, recorded } = fakeDeps(targets(), {
    t1: new Error("connection reset"),
    t2: { status: 429, reason: "TooManyRequests" },
  });
  assertEquals(await deliver(EVENT, deps), "failed");
  assertEquals(recorded, [{ status: "failed", invalid: [] }]);
});

Deno.test("recipient without devices is recorded without sending", async () => {
  const { deps, recorded, sent } = fakeDeps(targets({ tokens: [] }), {});
  assertEquals(await deliver(EVENT, deps), "no_devices");
  assertEquals(sent, []);
  assertEquals(recorded, [{ status: "no_devices", invalid: [] }]);
});

Deno.test("a retried event that APNs already accepted is not pushed twice", async () => {
  const { deps, recorded, sent } = fakeDeps(targets({ push_status: "accepted" }), {});
  assertEquals(await deliver(EVENT, deps), "accepted");
  assertEquals(sent, []);
  assertEquals(recorded, []);
});

Deno.test("a retried event whose push failed is pushed again", async () => {
  const { deps, sent } = fakeDeps(targets({ push_status: "failed" }), { t1: { status: 200 }, t2: { status: 200 } });
  assertEquals(await deliver(EVENT, deps), "accepted");
  assertEquals(sent.sort(), ["t1", "t2"]);
});
