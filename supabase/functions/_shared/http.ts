export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

/**
 * A database refusal as the app should see it. Codes the app acts on pass through
 * with their status. 401 stays 401 (the app refreshes its session on it) with a
 * fixed code. Anything else, such as a raw database or gateway message, is logged
 * here and answered with `fallback` and 500, so internals never reach the client.
 */
export function refusal(
  error: { message: string } | null,
  status: number,
  known: ReadonlySet<string>,
  fallback: string,
): Response {
  const message = error?.message ?? "";
  if (status === 401) return json({ error: "not_authenticated" }, 401);
  if (known.has(message) && status >= 400 && status < 500) return json({ error: message }, status);
  console.error(fallback, status, message);
  return json({ error: fallback }, 500);
}
