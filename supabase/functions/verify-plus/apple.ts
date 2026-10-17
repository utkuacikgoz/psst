// Apple's signed transactions, checked with WebCrypto. Apple's own Node library
// can't run here: Supabase Edge Functions run on Deno, whose node:crypto has no
// X509Certificate.verify() or .raw, and jsonwebtoken can't read EC key curves, so
// every verification failed with VERIFICATION_FAILURE (status=1). Same checks as
// Apple's library: the x5c chain up to one of Apple's roots, Apple's marker
// extensions on the leaf and intermediate, validity dates, then the ES256 signature.
import * as x509 from "npm:@peculiar/x509@1.12.3";
import { compactVerify, decodeProtectedHeader, importPKCS8, SignJWT } from "npm:jose@5.9.6";

export type AppleEnvironment = "Production" | "Sandbox";

/** Apple's marker on the App Store receipt-signing leaf certificate. */
export const LEAF_OID = "1.2.840.113635.100.6.11.1";
/** Apple's marker on the Worldwide Developer Relations intermediate. */
export const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

export interface TransactionPayload {
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  bundleId?: string;
  environment?: string;
  appAppleId?: number;
  appAccountToken?: string;
  revocationDate?: number;
}

export interface Expectation {
  bundleId: string;
  environment: AppleEnvironment;
  /** Production transactions name the app; checked when given. */
  appAppleId?: number;
}

function certificate(base64: string): x509.X509Certificate {
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return new x509.X509Certificate(bytes);
}

function current(cert: x509.X509Certificate, at: Date): boolean {
  return cert.notBefore <= at && at <= cert.notAfter;
}

export async function verifySignedTransaction(
  jws: string, rootsBase64: string[], expect: Expectation, now = new Date(),
): Promise<TransactionPayload> {
  if (!rootsBase64.length) throw new Error("Missing trust roots");
  const chain = decodeProtectedHeader(jws).x5c;
  if (!Array.isArray(chain) || chain.length !== 3) throw new Error("Invalid chain length");
  const leaf = certificate(chain[0]);
  const intermediate = certificate(chain[1]);

  let trusted: x509.X509Certificate | undefined;
  for (const root of rootsBase64.map(certificate)) {
    if (intermediate.issuer === root.subject &&
        await intermediate.verify({ publicKey: root.publicKey, signatureOnly: true })) {
      trusted = root;
      break;
    }
  }
  if (!trusted) throw new Error("Untrusted chain");
  if (leaf.issuer !== intermediate.subject ||
      !await leaf.verify({ publicKey: intermediate.publicKey, signatureOnly: true })) {
    throw new Error("Leaf not signed by intermediate");
  }
  if (!intermediate.getExtension(x509.BasicConstraintsExtension)?.ca) throw new Error("Intermediate is not a CA");
  if (!leaf.getExtension(LEAF_OID) || !intermediate.getExtension(INTERMEDIATE_OID)) {
    throw new Error("Not Apple's App Store certificates");
  }
  if (![leaf, intermediate, trusted].every((cert) => current(cert, now))) throw new Error("Certificate expired");

  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const { payload } = await compactVerify(jws, key, { algorithms: ["ES256"] });
  const transaction = JSON.parse(new TextDecoder().decode(payload)) as TransactionPayload;
  if (transaction.bundleId !== expect.bundleId) throw new Error("Wrong bundle");
  if (transaction.environment !== expect.environment) throw new Error("Wrong environment");
  if (expect.appAppleId !== undefined && transaction.appAppleId !== undefined &&
      transaction.appAppleId !== expect.appAppleId) {
    throw new Error("Wrong app");
  }
  return transaction;
}

export interface Credentials {
  privateKey: string;
  keyId: string;
  issuerId: string;
  bundleId: string;
}

const HOSTS: Record<AppleEnvironment, string> = {
  Production: "https://api.storekit.itunes.apple.com",
  Sandbox: "https://api.storekit-sandbox.itunes.apple.com",
};

/** Apple's current signed record of a transaction (App Store Server API, Get Transaction Info). */
export async function fetchSignedTransaction(
  transactionId: string, environment: AppleEnvironment, credentials: Credentials, fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const key = await importPKCS8(credentials.privateKey.replace(/\\n/g, "\n"), "ES256");
  const token = await new SignJWT({ bid: credentials.bundleId })
    .setProtectedHeader({ alg: "ES256", kid: credentials.keyId, typ: "JWT" })
    .setIssuer(credentials.issuerId)
    .setIssuedAt()
    .setExpirationTime("5m")
    .setAudience("appstoreconnect-v1")
    .sign(key);
  const response = await fetchImpl(`${HOSTS[environment]}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 200);
    throw new Error(`Apple http=${response.status} ${body}`);
  }
  const signed = (await response.json())?.signedTransactionInfo;
  if (typeof signed !== "string") throw new Error("Apple sent no signedTransactionInfo");
  return signed;
}
