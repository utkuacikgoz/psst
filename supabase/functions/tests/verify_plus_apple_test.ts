import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import * as x509 from "npm:@peculiar/x509@1.12.3";
import { CompactSign, decodeProtectedHeader } from "npm:jose@5.9.6";
import { fetchSignedTransaction, INTERMEDIATE_OID, LEAF_OID, verifySignedTransaction } from "../verify-plus/apple.ts";

// A stand-in for Apple's chain (root → WWDR intermediate → App Store leaf), with
// the same key types and Apple's marker extensions, made fresh for each run.
const NULL = new Uint8Array([5, 0]);
const ec = (namedCurve: string) =>
  crypto.subtle.generateKey({ name: "ECDSA", namedCurve }, true, ["sign", "verify"]) as Promise<CryptoKeyPair>;
const b64 = (cert: x509.X509Certificate) => btoa(String.fromCharCode(...new Uint8Array(cert.rawData)));
const year = 365 * 24 * 3600 * 1000;

async function chain(options: { leafMarker?: boolean } = {}) {
  const rootKeys = await ec("P-384"), interKeys = await ec("P-384"), leafKeys = await ec("P-256");
  const notBefore = new Date(Date.now() - year), notAfter = new Date(Date.now() + year);
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Test Root CA - G3, O=Test, C=US", notBefore, notAfter, keys: rootKeys,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Test WWDR - G6, O=Test, C=US", issuer: root.subject, notBefore, notAfter,
    publicKey: interKeys.publicKey, signingKey: rootKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, 0, true), new x509.Extension(INTERMEDIATE_OID, false, NULL)],
  });
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=Test Prod ECC Mac App Store, O=Test, C=US", issuer: intermediate.subject,
    notBefore, notAfter, publicKey: leafKeys.publicKey, signingKey: interKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: options.leafMarker === false ? [] : [new x509.Extension(LEAF_OID, false, NULL)],
  });
  const sign = (payload: object) =>
    new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
      .setProtectedHeader({ alg: "ES256", x5c: [b64(leaf), b64(intermediate), b64(root)] })
      .sign(leafKeys.privateKey);
  return { roots: [b64(root)], sign };
}

const purchase = {
  transactionId: "2000000111", originalTransactionId: "2000000100", productId: "psstplus.unlock",
  bundleId: "app.psst", environment: "Sandbox",
};
const expect = { bundleId: "app.psst", environment: "Sandbox" as const };

Deno.test("an Apple-shaped signed transaction verifies with WebCrypto", async () => {
  const { roots, sign } = await chain();
  const verified = await verifySignedTransaction(await sign(purchase), roots, expect);
  assertEquals([verified.productId, verified.originalTransactionId], ["psstplus.unlock", "2000000100"]);
});

Deno.test("anything not signed by the trusted chain, or for another app, is refused", async () => {
  const { roots, sign } = await chain();
  const other = await chain();
  const jws = await sign(purchase);
  await assertRejects(() => verifySignedTransaction(jws, other.roots, expect), Error, "Untrusted chain");
  const [header, , signature] = jws.split(".");
  const forged = `${header}.${btoa(JSON.stringify({ ...purchase, productId: "free" })).replace(/=+$/, "")}.${signature}`;
  await assertRejects(() => verifySignedTransaction(forged, roots, expect));
  const otherApp = await sign({ ...purchase, bundleId: "other.app" });
  await assertRejects(() => verifySignedTransaction(otherApp, roots, expect), Error, "Wrong bundle");
  await assertRejects(() => verifySignedTransaction(jws, roots, { ...expect, environment: "Production" }),
    Error, "Wrong environment");
  const unmarked = await chain({ leafMarker: false });
  const unmarkedJws = await unmarked.sign(purchase);
  await assertRejects(() => verifySignedTransaction(unmarkedJws, unmarked.roots, expect),
    Error, "Not Apple's App Store certificates");
  await assertRejects(() => verifySignedTransaction(jws, [], expect), Error, "Missing trust roots");
});

Deno.test("Apple's server API is asked with an ES256 token for the right environment", async () => {
  const keys = await ec("P-256");
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  let asked = "", header: Record<string, unknown> = {};
  const fake = ((url: string, init?: RequestInit) => {
    asked = url;
    header = decodeProtectedHeader((init!.headers as Record<string, string>).Authorization.slice(7));
    return Promise.resolve(new Response(JSON.stringify({ signedTransactionInfo: "a.b.c" })));
  }) as typeof fetch;
  const credentials = { privateKey: pem, keyId: "KEY123", issuerId: "issuer", bundleId: "app.psst" };
  assertEquals(await fetchSignedTransaction("2000000111", "Sandbox", credentials, fake), "a.b.c");
  assertEquals(asked, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/2000000111");
  assertEquals([header.alg, header.kid], ["ES256", "KEY123"]);
  const refused = (() => Promise.resolve(new Response("{\"errorCode\":4040010}", { status: 404 }))) as typeof fetch;
  await assertRejects(() => fetchSignedTransaction("1", "Production", credentials, refused), Error, "Apple http=404");
});
