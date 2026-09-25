import { ApnsEnvironment, ApnsResult, classify } from "./apns.ts";

export type PushStatus = "pending" | "accepted" | "failed" | "no_devices";

export interface PushTargets {
  event_id: string;
  connection_id: string;
  effect_id: string;
  push_status: PushStatus;
  sender_name: string;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

export interface DeliverDeps {
  pushTargets(eventId: string): Promise<PushTargets | null>;
  recordPushResult(eventId: string, status: PushStatus, invalidTokens: string[]): Promise<void>;
  sendPush(
    token: string,
    environment: ApnsEnvironment,
    payload: unknown,
    options: { apnsId: string; expiresAt: number },
  ): Promise<ApnsResult>;
  nowSeconds(): number;
}

const EFFECT_TITLES: Record<string, string> = {
  psst: "Psst",
};

/** A signal is a moment, not a message: undelivered pushes are dropped after an hour. */
export const PUSH_LIFETIME_SECONDS = 60 * 60;

/** The sender's name comes first; the app shows the effect when opened. */
export function buildPayload(targets: PushTargets) {
  return {
    aps: {
      alert: {
        title: targets.sender_name,
        body: EFFECT_TITLES[targets.effect_id] ?? "Signal",
      },
      sound: "default",
      category: "SIGNAL",
      "thread-id": targets.connection_id,
    },
    psst: {
      event_id: targets.event_id,
      connection_id: targets.connection_id,
      effect_id: targets.effect_id,
    },
  };
}

/**
 * Sends one alert per registered device of the recipient.
 * "accepted" means APNs accepted at least one request. It is not proof that a
 * device received or displayed anything; only the recipient's ack_signals is.
 * Safe to call again for the same event: an event APNs already accepted is not re-pushed.
 */
export async function deliver(eventId: string, deps: DeliverDeps): Promise<PushStatus> {
  const targets = await deps.pushTargets(eventId);
  if (!targets) return "failed";
  if (targets.push_status === "accepted") return "accepted";

  if (targets.tokens.length === 0) {
    await deps.recordPushResult(eventId, "no_devices", []);
    return "no_devices";
  }

  const payload = buildPayload(targets);
  const expiresAt = deps.nowSeconds() + PUSH_LIFETIME_SECONDS;
  const outcomes = await Promise.all(
    targets.tokens.map(async ({ token, environment }) => {
      try {
        const result = await deps.sendPush(token, environment, payload, { apnsId: eventId, expiresAt });
        return { token, outcome: classify(result) };
      } catch {
        return { token, outcome: "failed" as const };
      }
    }),
  );

  const invalid = outcomes.filter((o) => o.outcome === "invalid_token").map((o) => o.token);
  let status: PushStatus;
  if (outcomes.some((o) => o.outcome === "accepted")) status = "accepted";
  else if (invalid.length === outcomes.length) status = "no_devices";
  else status = "failed";

  await deps.recordPushResult(eventId, status, invalid);
  return status;
}
