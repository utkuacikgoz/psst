import { assertEquals } from "jsr:@std/assert@1";
import { buildRecapPayload, handleWeeklyRecap, WeeklyRecapDeps } from "../weekly-recap/handler.ts";

function request(auth: string | null) {
  const headers: Record<string, string> = {};
  if (auth) headers.authorization = auth;
  return new Request("http://localhost/weekly-recap", { method: "POST", headers, body: "{}" });
}

function deps(overrides: Partial<WeeklyRecapDeps> = {}) {
  const pushes: { token: string; payload: unknown }[] = [];
  const removed: string[][] = [];
  const d: WeeklyRecapDeps = {
    cronOk: (secret) => Promise.resolve(secret === "right"),
    targets: () => Promise.resolve([{
      user_id: "u1", title: "Your week: 38 Pssts", body: "Kim is still your #1.",
      tokens: [{ token: "good", environment: "production" }, { token: "gone", environment: "production" }],
    }]),
    removeTokens: (tokens) => { removed.push(tokens); return Promise.resolve(); },
    sendPush: (token, _env, payload) => {
      pushes.push({ token, payload });
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
  assertEquals(await res.json(), { people: 1, sent: 1 });
  assertEquals(pushes.map((p) => p.token), ["good", "gone"]);
  assertEquals(removed, [["gone"]]);
});

Deno.test("the push opens the recap", () => {
  const payload = buildRecapPayload({ user_id: "u", title: "Your week: 3 Pssts", body: "Ada is your #1.", tokens: [] });
  assertEquals(payload.psst, { recap: true });
  assertEquals(payload.aps.alert, { title: "Your week: 3 Pssts", body: "Ada is your #1." });
});
