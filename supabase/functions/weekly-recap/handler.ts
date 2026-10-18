import { json } from "../_shared/http.ts";
import { ApnsEnvironment, ApnsResult, classify } from "../_shared/apns.ts";

export interface RecapTarget {
  user_id: string;
  title: string;
  body: string;
  sound?: string;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

/** A Psst link nobody has opened by day 5 (owner pick 3A): one reminder to its sender. */
export interface InviteReminderTarget {
  user_id: string;
  code: string;
  sound?: string | null;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

export interface WeeklyRecapDeps {
  /** True only for the hourly job's secret (kept in the database's vault). */
  cronOk(secret: string): Promise<boolean>;
  /** Everyone due a recap now; the database marks them sent as it returns them. */
  targets(): Promise<RecapTarget[]>;
  /** Psst links due their one reminder; the database marks them reminded as it returns them. */
  inviteReminders(): Promise<InviteReminderTarget[]>;
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

/** The link still works for two more days; after a day the nudge is stale. */
export const INVITE_REMINDER_LIFETIME_SECONDS = 24 * 60 * 60;

/** Opening it shows the share sheet with the same link (owner pick 3A). */
export function buildInviteReminderPayload(target: InviteReminderTarget) {
  return {
    aps: {
      alert: { title: "Your Psst hasn't been opened", body: "Send it again?" },
      sound: target.sound ?? "psst.wav",
      "thread-id": "invite-reminder",
    },
    psst: { invite_reminder: true, code: target.code },
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
  // 50 people at a time: one at a time would run past the function's time limit
  // with a few thousand recipients, and they're already marked sent.
  const pushOne = async (target: RecapTarget) => {
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
  };
  for (let i = 0; i < targets.length; i += 50) {
    await Promise.all(targets.slice(i, i + 50).map(pushOne));
  }

  // After the recaps, the Psst link reminders (3A), on the same terms: best
  // effort, and each link is already marked reminded, so nobody gets two.
  const reminders = await deps.inviteReminders().catch(() => [] as InviteReminderTarget[]);
  const reminderExpiresAt = deps.nowSeconds() + INVITE_REMINDER_LIFETIME_SECONDS;
  let remindersSent = 0;
  const remindOne = async (target: InviteReminderTarget) => {
    const payload = buildInviteReminderPayload(target);
    await Promise.all(target.tokens.map(async ({ token, environment }) => {
      try {
        const result = await deps.sendPush(token, environment, payload, {
          apnsId: deps.newId(),
          expiresAt: reminderExpiresAt,
        });
        const outcome = classify(result);
        if (outcome === "invalid_token") invalid.push(token);
        if (outcome === "accepted") remindersSent += 1;
      } catch {
        // Best effort, as above.
      }
    }));
  };
  for (let i = 0; i < reminders.length; i += 50) {
    await Promise.all(reminders.slice(i, i + 50).map(remindOne));
  }

  if (invalid.length > 0) await deps.removeTokens([...new Set(invalid)]).catch(() => {});
  return json({ people: targets.length, sent, reminders: reminders.length, reminders_sent: remindersSent }, 200);
}
