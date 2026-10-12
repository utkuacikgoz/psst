import { json } from "../_shared/http.ts";
import { ApnsEnvironment, ApnsResult, classify } from "../_shared/apns.ts";

export interface AcceptResult {
  status: "accepted" | "already_connected";
  connection_id: string;
}

export interface JoinedTargets {
  connection_id: string;
  joiner_name: string;
  sound?: string;
  tokens: { token: string; environment: ApnsEnvironment }[];
}

export interface AcceptInviteDeps {
  /** Calls public.accept_invite as the caller (their JWT), so the database authorizes it. */
  acceptInvite(
    authorization: string,
    code: string,
  ): Promise<{ data: AcceptResult | null; error: { message: string } | null; status: number }>;
  joinedTargets(connectionId: string): Promise<JoinedTargets | null>;
  removeTokens(tokens: string[]): Promise<void>;
  sendPush(
    token: string,
    environment: ApnsEnvironment,
    payload: unknown,
    options: { apnsId: string; expiresAt: number },
  ): Promise<ApnsResult>;
  nowSeconds(): number;
}

/** A day is plenty: after that, they'll see the person on home anyway. */
export const JOINED_PUSH_LIFETIME_SECONDS = 24 * 60 * 60;

/** The joiner's name and what to do next. Opening it shows the J2 welcome in the app. */
export function buildJoinedPayload(targets: JoinedTargets) {
  return {
    aps: {
      alert: { title: `${targets.joiner_name} is in`, body: "Tap to send your first Psst" },
      sound: targets.sound ?? "psst.wav",
      "thread-id": targets.connection_id,
    },
    psst: { connection_id: targets.connection_id, joined: true },
  };
}

/**
 * POST { code } with the user's bearer token. Accepts the invite exactly as the
 * accept_invite RPC does, then tells the inviter once, on a fresh acceptance.
 * The push is best effort: acceptance never fails because of it.
 */
export async function handleAcceptInvite(req: Request, deps: AcceptInviteDeps): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("authorization");
  if (!authorization?.toLowerCase().startsWith("bearer ")) {
    return json({ error: "not_authenticated" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const code = body?.code;
  if (typeof code !== "string" || code.length === 0 || code.length > 64) {
    return json({ error: "invalid_body" }, 400);
  }

  const { data, error, status } = await deps.acceptInvite(authorization, code);
  if (error || !data) {
    return json({ error: error?.message ?? "accept_failed" }, status >= 400 ? status : 500);
  }

  if (data.status === "accepted") {
    try {
      await notifyInviter(data.connection_id, deps);
    } catch {
      // They'll still see the new person on home.
    }
  }
  return json(data, 200);
}

async function notifyInviter(connectionId: string, deps: AcceptInviteDeps) {
  const targets = await deps.joinedTargets(connectionId);
  if (!targets || targets.tokens.length === 0) return;
  const payload = buildJoinedPayload(targets);
  const expiresAt = deps.nowSeconds() + JOINED_PUSH_LIFETIME_SECONDS;
  const invalid: string[] = [];
  await Promise.all(targets.tokens.map(async ({ token, environment }) => {
    try {
      const result = await deps.sendPush(token, environment, payload, { apnsId: connectionId, expiresAt });
      if (classify(result) === "invalid_token") invalid.push(token);
    } catch {
      // Best effort.
    }
  }));
  if (invalid.length > 0) await deps.removeTokens(invalid);
}
