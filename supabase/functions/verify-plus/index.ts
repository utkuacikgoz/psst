import { createClient } from "jsr:@supabase/supabase-js@2";
import { type AppleEnvironment, fetchSignedTransaction, verifySignedTransaction } from "./apple.ts";
import { handleVerifyPlus } from "./handler.ts";
import { parseRoots } from "./roots.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

Deno.serve((req) => handleVerifyPlus(req, {
  async authenticate(authorization) {
    const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: { user }, error } = await caller.auth.getUser();
    return error ? null : user?.id ?? null;
  },
  async verify(proof) {
    // Fail closed unless explicitly configured. In Production, Apple's guidance is
    // to check Production first and then Sandbox: TestFlight and App Review buy in
    // Sandbox with the same production build. Sandbox purchases need a tester
    // account on this app's team, so this opens nothing to the public.
    const env = Deno.env.get("APP_STORE_ENVIRONMENT");
    if (env !== "Sandbox" && env !== "Production") {
      await logFailure("config", "APP_STORE_ENVIRONMENT not set");
      throw new Error("Not configured");
    }
    const order: AppleEnvironment[] = env === "Production" ? ["Production", "Sandbox"] : ["Sandbox"];
    let lastError: unknown;
    for (const environment of order) {
      try {
        return await verifyIn(environment, proof);
      } catch (error) {
        await logFailure(`verify ${environment}`, describe(error));
        lastError = error;
      }
    }
    throw lastError;
  },
  async isCurrent(userId) {
    const { data, error } = await service.rpc("plus_is_current", { p_user_id: userId });
    return !error && data === true;
  },
  async record(userId, purchase) {
    const { error } = await service.rpc("record_verified_plus", {
      p_user_id: userId, p_original_id: purchase.originalTransactionId, p_active: purchase.active,
    });
    if (error) {
      await logFailure("record", `${error.code ?? ""} ${error.message}`);
      throw new Error("Record refused");
    }
  },
}));

async function verifyIn(environment: AppleEnvironment, proof: string) {
  const bundleId = Deno.env.get("APP_STORE_BUNDLE_ID")!;
  const roots = parseRoots(Deno.env.get("APPLE_ROOT_CA_BASE64") ?? "");
  const expect = { bundleId, environment,
    appAppleId: environment === "Production" ? Number(Deno.env.get("APP_STORE_APP_ID")) : undefined };
  const device = await verifySignedTransaction(proof, roots, expect);
  if (device.productId !== "psstplus.unlock" || !device.transactionId || !device.originalTransactionId) {
    throw new Error("Invalid product");
  }
  // Apple's own, current record: catches refunds since the phone signed its copy.
  const signed = await fetchSignedTransaction(device.transactionId, environment, {
    privateKey: Deno.env.get("APP_STORE_PRIVATE_KEY")!, keyId: Deno.env.get("APP_STORE_KEY_ID")!,
    issuerId: Deno.env.get("APP_STORE_ISSUER_ID")!, bundleId,
  });
  const latest = await verifySignedTransaction(signed, roots, expect);
  if (latest.productId !== "psstplus.unlock" || latest.originalTransactionId !== device.originalTransactionId) {
    throw new Error("Invalid transaction");
  }
  return { originalTransactionId: latest.originalTransactionId,
    appAccountToken: latest.appAccountToken,
    active: latest.revocationDate === undefined };
}

/** The reason only, never the proof or a key: read back by the diagnose-purchases workflow. */
async function logFailure(stage: string, reason: string) {
  console.error("verify-plus failed", stage, reason);
  try {
    await service.rpc("log_purchase_failure", { p_stage: stage, p_reason: reason });
  } catch {
    // Diagnostics never change the answer.
  }
}

/** Apple's library errors carry a status (verification) or an HTTP status and API error code. */
function describe(error: unknown): string {
  const e = error as { name?: string; message?: string; status?: unknown; httpStatusCode?: unknown; apiError?: unknown; errorMessage?: unknown };
  return [e?.name, e?.message, e?.status !== undefined ? `status=${e.status}` : "",
    e?.httpStatusCode !== undefined ? `http=${e.httpStatusCode}` : "",
    e?.apiError !== undefined ? `apiError=${e.apiError}` : "",
    e?.errorMessage ? `apple=${e.errorMessage}` : ""].filter(Boolean).join(" ");
}
