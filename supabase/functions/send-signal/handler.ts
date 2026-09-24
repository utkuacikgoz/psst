import { isUuid, json } from "../_shared/http.ts";
import { PushStatus } from "../_shared/deliver.ts";

export interface SendSignalResult {
  id: string;
  created_at: string;
  push_status: PushStatus;
  duplicate: boolean;
}

export interface SendSignalDeps {
  /** Calls public.send_signal as the caller (their JWT), so the database authorizes it. */
  sendSignal(
    authorization: string,
    args: { p_event_id: string; p_connection_id: string; p_effect_id: string },
  ): Promise<{ data: SendSignalResult | null; error: { message: string } | null; status: number }>;
  deliver(eventId: string): Promise<PushStatus>;
}

/**
 * POST { event_id, connection_id, effect_id } with the user's bearer token.
 * 200 means the server accepted and stored the signal. push_status reports the
 * APNs hand-off only and must never be shown as delivery.
 */
export async function handleSendSignal(req: Request, deps: SendSignalDeps): Promise<Response> {
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
  const { event_id, connection_id, effect_id } = body ?? {};
  if (!isUuid(event_id) || !isUuid(connection_id) || typeof effect_id !== "string") {
    return json({ error: "invalid_body" }, 400);
  }

  const { data, error, status } = await deps.sendSignal(authorization, {
    p_event_id: event_id,
    p_connection_id: connection_id,
    p_effect_id: effect_id,
  });
  if (error || !data) {
    return json({ error: error?.message ?? "send_failed" }, status >= 400 ? status : 500);
  }

  let pushStatus: PushStatus = data.push_status;
  try {
    pushStatus = await deps.deliver(data.id);
  } catch {
    // The signal is stored and visible in the recipient's in-app inbox either way.
    pushStatus = "failed";
  }
  return json({ ...data, push_status: pushStatus }, 200);
}
