import { json } from "../_shared/http.ts";
import { ApnsEnvironment, ApnsResult, classify } from "../_shared/apns.ts";

export interface RecapTarget {
  user_id: string;
  title: string;
  body: string;
  sound?: string;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

export interface WeeklyRecapDeps {
  /** True only for the hourly job's secret (kept in the database's vault). */
  cronOk(secret: string): Promise<boolean>;
  /** Everyone due a recap now; the database marks them sent as it returns them. */
  targets(): Promise<RecapTarget[]>;
  removeTokens(tokens: string[]): Promise<void>;
  sendPush(
    token: string,
    environment: ApnsEnvironment,
    payload: unknown,
    options: { apnsId: string; expiresAt: number },
  ): Promise<ApnsResult>;
  nowSeconds(): number;
  newId(): string;
}

/** A recap is for this evening; after that it's stale. */
export const RECAP_PUSH_LIFETIME_SECONDS = 6 * 60 * 60;

/** Opening it shows the recap sheet in the app (owner pick 4A). */
export function buildRecapPayload(target: RecapTarget) {
  return {
    aps: {
      alert: { title: target.title, body: target.body },
      sound: target.sound ?? "psst.wav",
      "thread-id": "weekly-recap",
    },
    psst: { recap: true },
  };
}

/** POST from the hourly job with its secret as the bearer token. */
export async function handleWeeklyRecap(req: Request, deps: WeeklyRecapDeps): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization") ?? "";
  const secret = authorization.toLowerCase().startsWith("bearer ") ? authorization.slice(7).trim() : "";
  if (!secret || !(await deps.cronOk(secret).catch(() => false))) {
    return json({ error: "not_authenticated" }, 401);
  }

  const targets = await deps.targets();
  const expiresAt = deps.nowSeconds() + RECAP_PUSH_LIFETIME_SECONDS;
  const invalid: string[] = [];
  let sent = 0;
  for (const target of targets) {
    const payload = buildRecapPayload(target);
    await Promise.all(target.tokens.map(async ({ token, environment }) => {
      try {
        const result = await deps.sendPush(token, environment, payload, { apnsId: deps.newId(), expiresAt });
        const outcome = classify(result);
        if (outcome === "invalid_token") invalid.push(token);
        if (outcome === "accepted") sent += 1;
      } catch {
        // Best effort: it's marked sent either way, so nobody gets two.
      }
    }));
  }
  if (invalid.length > 0) await deps.removeTokens(invalid).catch(() => {});
  return json({ people: targets.length, sent }, 200);
}
