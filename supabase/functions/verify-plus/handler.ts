import { json } from "../_shared/http.ts";

export interface VerifiedPurchase {
  originalTransactionId: string;
  appAccountToken?: string;
  active: boolean;
}
export interface VerifyPlusDeps {
  authenticate(authorization: string): Promise<string | null>;
  /** Verifies device proof, then fetches fresh transaction status from Apple. */
  verify(proof: string): Promise<VerifiedPurchase>;
  record(userId: string, purchase: VerifiedPurchase): Promise<void>;
  /** True when this account was verified in the last few minutes: no need to ask Apple again. */
  isCurrent?(userId: string): Promise<boolean>;
}

export async function handleVerifyPlus(req: Request, deps: VerifyPlusDeps): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization");
  if (!authorization?.toLowerCase().startsWith("bearer ")) return json({ error: "not_authenticated" }, 401);
  const userId = await deps.authenticate(authorization);
  if (!userId) return json({ error: "not_authenticated" }, 401);
  let proof: unknown;
  try { proof = (await req.json())?.signed_transaction; } catch { return json({ error: "invalid_body" }, 400); }
  if (typeof proof !== "string" || proof.length > 30000 || proof.split(".").length !== 3) {
    return json({ error: "invalid_body" }, 400);
  }
  if (deps.isCurrent && await deps.isCurrent(userId).catch(() => false)) {
    return new Response(null, { status: 204 });
  }
  let purchase: VerifiedPurchase;
  try { purchase = await deps.verify(proof); }
  catch { return json({ error: "purchase_verification_unavailable" }, 503); }
  // Accounts are anonymous and live on one phone, so a restore on a new phone is a
  // new account: the account that proves the Apple-signed purchase now holds it,
  // and record_verified_plus moves it from the previous one.
  try { await deps.record(userId, purchase); }
  catch { return json({ error: "purchase_record_failed" }, 503); }
  if (!purchase.active) return json({ error: "purchase_revoked" }, 403);
  return new Response(null, { status: 204 });
}
