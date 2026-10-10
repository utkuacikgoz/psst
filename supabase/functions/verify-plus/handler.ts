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
  let purchase: VerifiedPurchase;
  try { purchase = await deps.verify(proof); }
  catch { return json({ error: "purchase_verification_unavailable" }, 503); }
  // New purchases are bound at checkout. Older signed purchases can be claimed
  // once by record_verified_plus, which enforces unique original transaction ID.
  if (purchase.appAccountToken && purchase.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    return json({ error: "purchase_account_mismatch" }, 403);
  }
  try { await deps.record(userId, purchase); }
  catch { return json({ error: "purchase_already_linked" }, 409); }
  if (!purchase.active) return json({ error: "purchase_revoked" }, 403);
  return new Response(null, { status: 204 });
}
