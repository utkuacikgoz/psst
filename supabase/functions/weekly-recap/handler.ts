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
  /** Which link (13A): a Psst link holding a doodle, a plain Psst link, or a group code. */
  kind?: InviteKind;
  sound?: string | null;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

export type InviteKind = "doodle" | "psst" | "code";

/** A 3+ day streak that ends at midnight, for someone with the streak saver on (5A). */
export interface StreakReminderTarget {
  user_id: string;
  connection_id: string;
  /** "Your 6-day streak with Mia ends at midnight 🔥" */
  body: string;
  sound?: string | null;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

/** A quiet week after a busy one (11A): "Quiet week. Psst Kim?" */
export interface QuietWeekTarget {
  user_id: string;
  connection_id: string;
  body: string;
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
  /** 8 PM streak reminders due now; the database claims the day as it returns them. */
  streakReminders(): Promise<StreakReminderTarget[]>;
  /** Sunday quiet-week pushes due now; the database marks them sent as it returns them. */
  quietWeeks(): Promise<QuietWeekTarget[]>;
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

/** Opening it shows the share sheet with the same link (owner picks 3A, 13A). */
export function buildInviteReminderPayload(target: InviteReminderTarget) {
  return {
    aps: {
      alert: { title: "Your Psst is still waiting", body: "Send it again?" },
      sound: target.sound ?? "psst.wav",
      "thread-id": "invite-reminder",
    },
    psst: { invite_reminder: true, code: target.code, kind: target.kind ?? "psst" },
  };
}

/** Only useful until midnight. */
export const STREAK_REMINDER_LIFETIME_SECONDS = 4 * 60 * 60;

/** Body only, like a Psst: iOS shows the app name above it (5A). Opens that band. */
export function buildStreakReminderPayload(target: StreakReminderTarget) {
  return {
    aps: {
      alert: { body: target.body },
      sound: target.sound ?? "psst.wav",
      "thread-id": "streak-reminder",
    },
    psst: { streak_reminder: true, connection_id: target.connection_id },
  };
}

/** A Sunday-evening nudge; stale by the next day. */
export const QUIET_WEEK_LIFETIME_SECONDS = 6 * 60 * 60;

/** Body only (11A). Opens that person's band. */
export function buildQuietWeekPayload(target: QuietWeekTarget) {
  return {
    aps: {
      alert: { body: target.body },
      sound: target.sound ?? "psst.wav",
      "thread-id": "quiet-week",
    },
    psst: { quiet_week: true, connection_id: target.connection_id },
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

  // After the recaps, the other pushes of the hourly run, on the same terms: best
  // effort, and each is already marked sent in the database, so nobody gets two.
  // A failing lookup skips that kind only.
  const sendAll = async <T extends { tokens: { token: string; environment: ApnsEnvironment }[] }>(
    lookup: () => Promise<T[]>,
    build: (target: T) => unknown,
    lifetime: number,
  ) => {
    const list = await lookup().catch(() => [] as T[]);
    const until = deps.nowSeconds() + lifetime;
    let accepted = 0;
    const one = async (target: T) => {
      const payload = build(target);
      await Promise.all(target.tokens.map(async ({ token, environment }) => {
        try {
          const result = await deps.sendPush(token, environment, payload, { apnsId: deps.newId(), expiresAt: until });
          const outcome = classify(result);
          if (outcome === "invalid_token") invalid.push(token);
          if (outcome === "accepted") accepted += 1;
        } catch {
          // Best effort, as above.
        }
      }));
    };
    for (let i = 0; i < list.length; i += 50) {
      await Promise.all(list.slice(i, i + 50).map(one));
    }
    return { people: list.length, sent: accepted };
  };

  const reminders = await sendAll(
    () => deps.inviteReminders(),
    buildInviteReminderPayload,
    INVITE_REMINDER_LIFETIME_SECONDS,
  );
  const streaks = await sendAll(
    () => deps.streakReminders(),
    buildStreakReminderPayload,
    STREAK_REMINDER_LIFETIME_SECONDS,
  );
  const quiet = await sendAll(() => deps.quietWeeks(), buildQuietWeekPayload, QUIET_WEEK_LIFETIME_SECONDS);

  if (invalid.length > 0) await deps.removeTokens([...new Set(invalid)]).catch(() => {});
  return json({
    people: targets.length,
    sent,
    reminders: reminders.people,
    reminders_sent: reminders.sent,
    streak_reminders: streaks.people,
    streak_reminders_sent: streaks.sent,
    quiet_weeks: quiet.people,
    quiet_weeks_sent: quiet.sent,
  }, 200);
}
