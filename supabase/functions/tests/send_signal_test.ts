import { assertEquals } from "jsr:@std/assert@1";
import { handleSendSignal, SendSignalDeps } from "../send-signal/handler.ts";

const BODY = {
  event_id: "11111111-1111-4111-8111-111111111111",
  connection_id: "22222222-2222-4222-8222-222222222222",
  effect_id: "psst",
};

function request(body: unknown, auth: string | null = "Bearer user-jwt", method = "POST") {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (auth) headers.authorization = auth;
  return new Request("http://localhost/send-signal", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

function deps(overrides: Partial<SendSignalDeps> = {}) {
  const calls: { auth: string; args: unknown }[] = [];
  const d: SendSignalDeps = {
    sendSignal: (auth, args) => {
      calls.push({ auth, args });
      return Promise.resolve({
        data: { id: BODY.event_id, created_at: "2026-09-24T00:00:00Z", push_status: "pending", duplicate: false },
        error: null,
        status: 200,
      });
    },
    deliver: () => Promise.resolve("accepted"),
    ...overrides,
  };
  return { d, calls };
}

Deno.test("forwards the caller's own token and reports push status separately", async () => {
  const { d, calls } = deps();
  const res = await handleSendSignal(request(BODY), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    id: BODY.event_id,
    created_at: "2026-09-24T00:00:00Z",
    push_status: "accepted",
    duplicate: false,
  });
  assertEquals(calls, [{
    auth: "Bearer user-jwt",
    args: { p_event_id: BODY.event_id, p_connection_id: BODY.connection_id, p_effect_id: "psst" },
  }]);
});

Deno.test("rejects missing auth, wrong method and malformed bodies without calling the database", async () => {
  const { d, calls } = deps();
  assertEquals((await handleSendSignal(request(BODY, null), d)).status, 401);
  assertEquals((await handleSendSignal(request(BODY, "Bearer x", "GET"), d)).status, 405);
  assertEquals((await handleSendSignal(request({ ...BODY, event_id: "nope" }), d)).status, 400);
  assertEquals((await handleSendSignal(request({ ...BODY, effect_id: 3 }), d)).status, 400);
  assertEquals(calls.length, 0);
});

Deno.test("database refusals pass through with their status and do not push", async () => {
  let delivered = false;
  const { d } = deps({
    sendSignal: () => Promise.resolve({ data: null, error: { message: "not_connected" }, status: 403 }),
    deliver: () => {
      delivered = true;
      return Promise.resolve("accepted");
    },
  });
  const res = await handleSendSignal(request(BODY), d);
  assertEquals(res.status, 403);
  assertEquals(await res.json(), { error: "not_connected" });
  assertEquals(delivered, false);
});

Deno.test("a push failure still returns the stored signal", async () => {
  const { d } = deps({ deliver: () => Promise.reject(new Error("apns down")) });
  const res = await handleSendSignal(request(BODY), d);
  assertEquals(res.status, 200);
  assertEquals((await res.json()).push_status, "failed");
});
