import { assertEquals } from "jsr:@std/assert@1";
import {
  buildInviteReminderPayload,
  buildRecapPayload,
  handleWeeklyRecap,
  INVITE_REMINDER_LIFETIME_SECONDS,
  WeeklyRecapDeps,
} from "../weekly-recap/handler.ts";

function request(auth: string | null) {
  const headers: Record<string, string> = {};
  if (auth) headers.authorization = auth;
  return new Request("http://localhost/weekly-recap", { method: "POST", headers, body: "{}" });
}

function deps(overrides: Partial<WeeklyRecapDeps> = {}) {
  const pushes: { token: string; payload: unknown; expiresAt: number }[] = [];
  const removed: string[][] = [];
  const d: WeeklyRecapDeps = {
    cronOk: (secret) => Promise.resolve(secret === "right"),
    targets: () => Promise.resolve([{
      user_id: "u1", title: "Your week: 38 Pssts", body: "Kim is still your #1.",
      tokens: [{ token: "good", environment: "production" }, { token: "gone", environment: "production" }],
    }]),
    inviteReminders: () => Promise.resolve([]),
    removeTokens: (tokens) => { removed.push(tokens); return Promise.resolve(); },
    sendPush: (token, _env, payload, options) => {
      pushes.push({ token, payload, expiresAt: options.expiresAt });
      return Promise.resolve(token === "gone" ? { status: 410 } : { status: 200 });
    },
    nowSeconds: () => 1_000,
    newId: () => "33333333-3333-4333-8333-333333333333",
    ...overrides,
  };
  return { d, pushes, removed };
}

Deno.test("only the hourly job's secret runs it", async () => {
  const { d, pushes } = deps();
  assertEquals((await handleWeeklyRecap(request(null), d)).status, 401);
  assertEquals((await handleWeeklyRecap(request("Bearer wrong"), d)).status, 401);
  assertEquals(pushes.length, 0);
});

Deno.test("sends each person's recap and cleans dead tokens", async () => {
  const { d, pushes, removed } = deps();
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 0, reminders_sent: 0 });
  assertEquals(pushes.map((p) => p.token), ["good", "gone"]);
  assertEquals(removed, [["gone"]]);
});

Deno.test("the push opens the recap", () => {
  const payload = buildRecapPayload({ user_id: "u", title: "Your week: 3 Pssts", body: "Ada is your #1.", tokens: [] });
  assertEquals(payload.psst, { recap: true });
  assertEquals(payload.aps.alert, { title: "Your week: 3 Pssts", body: "Ada is your #1." });
});

Deno.test("after the recaps, an unopened Psst link reminds its sender once (3A)", async () => {
  const { d, pushes, removed } = deps({
    inviteReminders: () => Promise.resolve([{
      user_id: "u2", code: "ABCD2345", sound: "psst-soft.wav",
      tokens: [{ token: "phone", environment: "production" }, { token: "old", environment: "sandbox" }],
    }]),
    sendPush: (token, _env, payload, options) => {
      pushes.push({ token, payload, expiresAt: options.expiresAt });
      return Promise.resolve(token === "gone" || token === "old" ? { status: 410 } : { status: 200 });
    },
  });
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 1, reminders_sent: 1 });
  assertEquals(pushes.map((p) => p.token), ["good", "gone", "phone", "old"], "recaps first, then reminders");
  assertEquals(pushes[2].payload, {
    aps: {
      alert: { title: "Your Psst hasn't been opened", body: "Send it again?" },
      sound: "psst-soft.wav",
      "thread-id": "invite-reminder",
    },
    psst: { invite_reminder: true, code: "ABCD2345" },
  });
  assertEquals(pushes[2].expiresAt, 1_000 + INVITE_REMINDER_LIFETIME_SECONDS);
  assertEquals(removed, [["gone", "old"]], "dead tokens from both kinds removed in one call");
});

Deno.test("a failing reminder lookup or push never breaks the recap run", async () => {
  const { d, pushes } = deps({
    inviteReminders: () => Promise.reject(new Error("db down")),
  });
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 0, reminders_sent: 0 });
  assertEquals(pushes.length, 2);

  const { d: d2 } = deps({
    targets: () => Promise.resolve([]),
    inviteReminders: () => Promise.resolve([{ user_id: "u", code: "C0DE", tokens: [{ token: "t", environment: "production" }] }]),
    sendPush: () => Promise.reject(new Error("network")),
  });
  const res2 = await handleWeeklyRecap(request("Bearer right"), d2);
  assertEquals(await res2.json(), { people: 0, sent: 0, reminders: 1, reminders_sent: 0 });
});

Deno.test("the reminder falls back to the Psst sound", () => {
  const payload = buildInviteReminderPayload({ user_id: "u", code: "XYZ", sound: null, tokens: [] });
  assertEquals(payload.aps.sound, "psst.wav");
  assertEquals(payload.psst, { invite_reminder: true, code: "XYZ" });
});
