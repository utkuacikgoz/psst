import { assertEquals } from "jsr:@std/assert@1";
import { AcceptInviteDeps, buildJoinedPayload, handleAcceptInvite } from "../accept-invite/handler.ts";

const CONNECTION = "22222222-2222-4222-8222-222222222222";

function request(body: unknown, auth: string | null = "Bearer user-jwt") {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (auth) headers.authorization = auth;
  return new Request("http://localhost/accept-invite", { method: "POST", headers, body: JSON.stringify(body) });
}

function deps(status: "accepted" | "already_connected" = "accepted", overrides: Partial<AcceptInviteDeps> = {}) {
  const pushes: { token: string; payload: unknown }[] = [];
  const removed: string[][] = [];
  const d: AcceptInviteDeps = {
    acceptInvite: () => Promise.resolve({ data: { status, connection_id: CONNECTION }, error: null, status: 200 }),
    joinedTargets: () =>
      Promise.resolve({
        connection_id: CONNECTION,
        joiner_name: "Kim",
        tokens: [{ token: "good", environment: "sandbox" }, { token: "gone", environment: "sandbox" }],
      }),
    removeTokens: (tokens) => {
      removed.push(tokens);
      return Promise.resolve();
    },
    sendPush: (token, _env, payload) => {
      pushes.push({ token, payload });
      return Promise.resolve(token === "gone" ? { status: 410 } : { status: 200 });
    },
    nowSeconds: () => 1_000,
    ...overrides,
  };
  return { d, pushes, removed };
}

Deno.test("a fresh acceptance tells the inviter who joined and cleans dead tokens", async () => {
  const { d, pushes, removed } = deps();
  const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
  assertEquals(res.status, 200);
  assertEquals((await res.json()).status, "accepted");
  assertEquals(pushes.map((p) => p.token).sort(), ["gone", "good"]);
  assertEquals(removed, [["gone"]]);
});

Deno.test("already connected sends no push", async () => {
  const { d, pushes } = deps("already_connected");
  const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
  assertEquals(res.status, 200);
  assertEquals(pushes.length, 0);
});

Deno.test("invite errors keep their status and code for the app", async () => {
  const { d, pushes } = deps("accepted", {
    acceptInvite: () => Promise.resolve({ data: null, error: { message: "invite_used" }, status: 409 }),
  });
  const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { error: "invite_used" });
  assertEquals(pushes.length, 0);
});

Deno.test("a failing push never fails the acceptance", async () => {
  const { d } = deps("accepted", { joinedTargets: () => Promise.reject(new Error("down")) });
  const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
  assertEquals(res.status, 200);
});

Deno.test("needs a signed-in caller and a code", async () => {
  assertEquals((await handleAcceptInvite(request({ code: "X" }, null), deps().d)).status, 401);
  assertEquals((await handleAcceptInvite(request({}), deps().d)).status, 400);
});

Deno.test("the joined push names the person and carries no content", () => {
  const payload = buildJoinedPayload({ connection_id: CONNECTION, joiner_name: "Kim", tokens: [] });
  assertEquals(payload.aps.alert, { title: "Kim is in", body: "Tap to send your first Psst" });
  assertEquals(payload.psst, { connection_id: CONNECTION, joined: true });
});

Deno.test("joining through your Psst says so", () => {
  const payload = buildJoinedPayload({ connection_id: CONNECTION, joiner_name: "Kim", held_psst: true, tokens: [] });
  assertEquals(payload.aps.alert, { title: "Kim is in", body: "Kim got your Psst and joined. Tap to psst them." });
  const drawn = buildJoinedPayload({ connection_id: CONNECTION, joiner_name: "Kim", held_psst: true, held_doodle: true, tokens: [] });
  assertEquals(drawn.aps.alert.body, "Kim got your doodle and joined. Tap to psst them.");
});

Deno.test("invite refusals pass through; anything else is a fixed accept_failed", async () => {
  const errors: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => errors.push(args);
  try {
    for (const [message, status] of [["invite_invalid", 404], ["invite_own", 409], ["invite_revoked", 410],
      ["invite_expired", 410], ["too_many_attempts", 429], ["profile_required", 409]] as const) {
      const { d } = deps("accepted", { acceptInvite: () => Promise.resolve({ data: null, error: { message }, status }) });
      const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
      assertEquals([res.status, await res.json()], [status, { error: message }]);
    }
    // A raw message must not reach the app, nor look like a missing function (404 without invite_).
    for (const [message, status] of [['relation "public.invites" does not exist', 404], ["boom", 500]] as const) {
      const { d, pushes } = deps("accepted", { acceptInvite: () => Promise.resolve({ data: null, error: { message }, status }) });
      const res = await handleAcceptInvite(request({ code: "K7QX4MPA" }), d);
      assertEquals([res.status, await res.json()], [500, { error: "accept_failed" }]);
      assertEquals(pushes.length, 0);
    }
    assertEquals(errors.length, 2);
  } finally {
    console.error = original;
  }
  const { d } = deps("accepted", { acceptInvite: () => Promise.resolve({ data: null, error: { message: "JWT expired" }, status: 401 }) });
  assertEquals((await handleAcceptInvite(request({ code: "K7QX4MPA" }), d)).status, 401);
});
