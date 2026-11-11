import { assertEquals } from "jsr:@std/assert@1";
import {
  buildInviteReminderPayload,
  buildQuietWeekPayload,
  buildRecapPayload,
  buildStreakReminderPayload,
  handleWeeklyRecap,
  INVITE_REMINDER_LIFETIME_SECONDS,
  QUIET_WEEK_LIFETIME_SECONDS,
  STREAK_REMINDER_LIFETIME_SECONDS,
  WeeklyRecapDeps,
} from "../weekly-recap/handler.ts";

const NONE = { streak_reminders: 0, streak_reminders_sent: 0, quiet_weeks: 0, quiet_weeks_sent: 0 };

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
    streakReminders: () => Promise.resolve([]),
    quietWeeks: () => Promise.resolve([]),
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
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 0, reminders_sent: 0, ...NONE });
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
      user_id: "u2", code: "ABCD2345", kind: "doodle", sound: "psst-soft.wav",
      tokens: [{ token: "phone", environment: "production" }, { token: "old", environment: "sandbox" }],
    }]),
    sendPush: (token, _env, payload, options) => {
      pushes.push({ token, payload, expiresAt: options.expiresAt });
      return Promise.resolve(token === "gone" || token === "old" ? { status: 410 } : { status: 200 });
    },
  });
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 1, reminders_sent: 1, ...NONE });
  assertEquals(pushes.map((p) => p.token), ["good", "gone", "phone", "old"], "recaps first, then reminders");
  assertEquals(pushes[2].payload, {
    aps: {
      alert: { title: "Your Psst is still waiting", body: "Send it again?" },
      sound: "psst-soft.wav",
      "thread-id": "invite-reminder",
    },
    psst: { invite_reminder: true, code: "ABCD2345", kind: "doodle" },
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
  assertEquals(await res.json(), { people: 1, sent: 1, reminders: 0, reminders_sent: 0, ...NONE });
  assertEquals(pushes.length, 2);

  const { d: d2 } = deps({
    targets: () => Promise.resolve([]),
    inviteReminders: () => Promise.resolve([{ user_id: "u", code: "C0DE", tokens: [{ token: "t", environment: "production" }] }]),
    sendPush: () => Promise.reject(new Error("network")),
  });
  const res2 = await handleWeeklyRecap(request("Bearer right"), d2);
  assertEquals(await res2.json(), { people: 0, sent: 0, reminders: 1, reminders_sent: 0, ...NONE });
});

Deno.test("the reminder falls back to the Psst sound", () => {
  const payload = buildInviteReminderPayload({ user_id: "u", code: "XYZ", sound: null, tokens: [] });
  assertEquals(payload.aps.sound, "psst.wav");
  assertEquals(payload.psst, { invite_reminder: true, code: "XYZ", kind: "psst" });
  const code = buildInviteReminderPayload({ user_id: "u", code: "G1", kind: "code", tokens: [] });
  assertEquals(code.psst, { invite_reminder: true, code: "G1", kind: "code" });
  assertEquals(code.aps.alert, { title: "Your Psst is still waiting", body: "Send it again?" });
});

Deno.test("streak reminders and quiet weeks go out after the recaps (5A, 11A)", async () => {
  const { d, pushes, removed } = deps({
    streakReminders: () => Promise.resolve([{
      user_id: "u3", connection_id: "c-mia", body: "Your 6-day streak with Mia ends at midnight 🔥",
      sound: "psst-soft.wav", tokens: [{ token: "s1", environment: "production" }],
    }]),
    quietWeeks: () => Promise.resolve([{
      user_id: "u4", connection_id: "c-kim", body: "Quiet week. Psst Kim?",
      tokens: [{ token: "q1", environment: "sandbox" }, { token: "qdead", environment: "sandbox" }],
    }]),
    sendPush: (token, _env, payload, options) => {
      pushes.push({ token, payload, expiresAt: options.expiresAt });
      return Promise.resolve(token === "gone" || token === "qdead" ? { status: 410 } : { status: 200 });
    },
  });
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(await res.json(), {
    people: 1, sent: 1, reminders: 0, reminders_sent: 0,
    streak_reminders: 1, streak_reminders_sent: 1, quiet_weeks: 1, quiet_weeks_sent: 1,
  });
  assertEquals(pushes.map((p) => p.token), ["good", "gone", "s1", "q1", "qdead"]);
  assertEquals(pushes[2].payload, {
    aps: {
      alert: { body: "Your 6-day streak with Mia ends at midnight 🔥" },
      sound: "psst-soft.wav",
      "thread-id": "streak-reminder",
    },
    psst: { streak_reminder: true, connection_id: "c-mia" },
  });
  assertEquals(pushes[2].expiresAt, 1_000 + STREAK_REMINDER_LIFETIME_SECONDS);
  assertEquals(pushes[3].payload, {
    aps: { alert: { body: "Quiet week. Psst Kim?" }, sound: "psst.wav", "thread-id": "quiet-week" },
    psst: { quiet_week: true, connection_id: "c-kim" },
  });
  assertEquals(pushes[3].expiresAt, 1_000 + QUIET_WEEK_LIFETIME_SECONDS);
  assertEquals(removed, [["gone", "qdead"]]);
});

Deno.test("a failing streak or quiet-week lookup skips only that kind", async () => {
  const { d, pushes } = deps({
    streakReminders: () => Promise.reject(new Error("db down")),
    quietWeeks: () => Promise.resolve([{ user_id: "u", connection_id: "c", body: "Quiet week. Psst Ada?", tokens: [{ token: "q", environment: "production" }] }]),
  });
  const res = await handleWeeklyRecap(request("Bearer right"), d);
  assertEquals(await res.json(), {
    people: 1, sent: 1, reminders: 0, reminders_sent: 0,
    streak_reminders: 0, streak_reminders_sent: 0, quiet_weeks: 1, quiet_weeks_sent: 1,
  });
  assertEquals(pushes.map((p) => p.token), ["good", "gone", "q"]);
  assertEquals(buildStreakReminderPayload({ user_id: "u", connection_id: "c", body: "b", tokens: [] }).aps.sound, "psst.wav");
  assertEquals(buildQuietWeekPayload({ user_id: "u", connection_id: "c", body: "b", sound: "x.wav", tokens: [] }).aps.sound, "x.wav");
});
