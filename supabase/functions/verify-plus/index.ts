import { Buffer } from "node:buffer";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AppStoreServerAPIClient, Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import { handleVerifyPlus } from "./handler.ts";

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
      console.error("verify-plus failed config", "APP_STORE_ENVIRONMENT not set");
      throw new Error("Not configured");
    }
    const order = env === "Production" ? [Environment.PRODUCTION, Environment.SANDBOX] : [Environment.SANDBOX];
    let lastError: unknown;
    for (const environment of order) {
      try {
        return await verifyIn(environment, proof);
      } catch (error) {
        // The reason only, never the proof or a key: read back by the diagnose-purchases workflow.
        console.error("verify-plus failed", environment, describe(error));
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
      console.error("verify-plus failed record", error.code ?? "", error.message);
      throw new Error("Record refused");
    }
  },
}));

async function verifyIn(environment: Environment, proof: string) {
  const bundle = Deno.env.get("APP_STORE_BUNDLE_ID")!;
  const roots: string[] = JSON.parse(Deno.env.get("APPLE_ROOT_CA_BASE64") ?? "[]");
  if (!roots.length) throw new Error("Missing trust roots");
  const production = environment === Environment.PRODUCTION;
  const verifier = new SignedDataVerifier(roots.map(root => Buffer.from(root, "base64")), true,
    environment, bundle, production ? Number(Deno.env.get("APP_STORE_APP_ID")) : undefined);
  const device = await verifier.verifyAndDecodeTransaction(proof);
  if (device.productId !== "psstplus.unlock" || !device.transactionId || !device.originalTransactionId) {
    throw new Error("Invalid product");
  }
  const apple = new AppStoreServerAPIClient(Deno.env.get("APP_STORE_PRIVATE_KEY")!,
    Deno.env.get("APP_STORE_KEY_ID")!, Deno.env.get("APP_STORE_ISSUER_ID")!, bundle, environment);
  const info = await apple.getTransactionInfo(device.transactionId);
  const current = await verifier.verifyAndDecodeTransaction(info.signedTransactionInfo!);
  if (current.productId !== "psstplus.unlock" || current.originalTransactionId !== device.originalTransactionId) {
    throw new Error("Invalid transaction");
  }
  return { originalTransactionId: current.originalTransactionId,
    appAccountToken: current.appAccountToken,
    active: current.revocationDate === undefined };
}

/** Apple's library errors carry a status (verification) or an HTTP status and API error code. */
function describe(error: unknown): string {
  const e = error as { name?: string; message?: string; status?: unknown; httpStatusCode?: unknown; apiError?: unknown; errorMessage?: unknown };
  return [e?.name, e?.message, e?.status !== undefined ? `status=${e.status}` : "",
    e?.httpStatusCode !== undefined ? `http=${e.httpStatusCode}` : "",
    e?.apiError !== undefined ? `apiError=${e.apiError}` : "",
    e?.errorMessage ? `apple=${e.errorMessage}` : ""].filter(Boolean).join(" ");
}
