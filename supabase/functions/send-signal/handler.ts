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
    args: { p_event_id: string; p_connection_id: string; p_effect_id: string; p_doodle?: unknown },
  ): Promise<{ data: SendSignalResult | null; error: { message: string } | null; status: number }>;
  deliver(eventId: string): Promise<PushStatus>;
  /**
   * Keeps work running after the response is sent (EdgeRuntime.waitUntil). With it,
   * the sender gets their answer as soon as the signal is stored and the push hand-off
   * to Apple happens afterwards, so "sending" doesn't wait on APNs.
   */
  background?(work: Promise<unknown>): void;
}

/**
 * POST { event_id, connection_id, effect_id } with the user's bearer token.
 * 200 means the server accepted and stored the signal. push_status reports the
 * APNs hand-off only and must never be shown as delivery; when the hand-off runs
 * in the background it is the stored status at answer time (usually "pending").
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
  const { event_id, connection_id, effect_id, doodle } = body ?? {};
  if (!isUuid(event_id) || !isUuid(connection_id) || typeof effect_id !== "string" ||
      (doodle !== undefined && !Array.isArray(doodle))) {
    return json({ error: "invalid_body" }, 400);
  }

  // A doodle's strokes; the database checks their shape and size.
  const { data, error, status } = await deps.sendSignal(authorization, {
    p_event_id: event_id,
    p_connection_id: connection_id,
    p_effect_id: effect_id,
    ...(doodle !== undefined ? { p_doodle: doodle } : {}),
  });
  if (error || !data) {
    return json({ error: error?.message ?? "send_failed" }, status >= 400 ? status : 500);
  }

  if (deps.background) {
    // The signal is stored and visible in the recipient's in-app inbox either way.
    deps.background(deps.deliver(data.id).catch((err) => {
      // Nobody awaits this, so say what went wrong in the function logs (no names or tokens).
      console.error("background push failed", data.id, err instanceof Error ? err.message : String(err));
      return "failed" as const;
    }));
    return json(data, 200);
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
