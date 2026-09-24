import { assert, assertEquals } from "jsr:@std/assert@1";
import { ApnsClient, ApnsConfig, classify, createProviderToken } from "../_shared/apns.ts";

async function testConfig(): Promise<{ config: ApnsConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const b of der) binary += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----`;
  return {
    config: { teamId: "TEAM123456", keyId: "KEY1234567", privateKeyPem: pem, bundleId: "app.psst.prototype" },
    publicKey: pair.publicKey,
  };
}

function decode(part: string): Uint8Array {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

Deno.test("provider token is a verifiable ES256 JWT with kid, iss and iat", async () => {
  const { config, publicKey } = await testConfig();
  const token = await createProviderToken(config, 1_700_000_000);
  const [header, claims, signature] = token.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(decode(header))), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(JSON.parse(new TextDecoder().decode(decode(claims))), { iss: "TEAM123456", iat: 1_700_000_000 });
  const sig = decode(signature);
  assertEquals(sig.length, 64);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      sig.buffer as ArrayBuffer,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
});

Deno.test("client reuses the provider token for 50 minutes and targets the right host", async () => {
  const { config } = await testConfig();
  let now = 1_700_000_000;
  const calls: { url: string; headers: Record<string, string>; body: string }[] = [];
  const fakeFetch = (async (url: string, init: RequestInit) => {
    calls.push({ url, headers: init.headers as Record<string, string>, body: init.body as string });
    return new Response(null, { status: 200 });
  }) as unknown as typeof fetch;
  const client = new ApnsClient(config, fakeFetch, () => now);

  await client.send("aa", "sandbox", { aps: {} }, { apnsId: "id-1", expiresAt: 5 });
  now += 49 * 60;
  await client.send("bb", "production", { aps: {} });
  now += 2 * 60;
  await client.send("cc", "production", { aps: {} });

  assertEquals(calls[0].url, "https://api.sandbox.push.apple.com/3/device/aa");
  assertEquals(calls[1].url, "https://api.push.apple.com/3/device/bb");
  assertEquals(calls[0].headers["apns-push-type"], "alert");
  assertEquals(calls[0].headers["apns-topic"], "app.psst.prototype");
  assertEquals(calls[0].headers["apns-id"], "id-1");
  assertEquals(calls[0].headers["apns-expiration"], "5");
  assertEquals(calls[0].headers.authorization, calls[1].headers.authorization);
  assert(calls[2].headers.authorization !== calls[1].headers.authorization);
});

Deno.test("error reasons are read from the response body", async () => {
  const { config } = await testConfig();
  const fakeFetch = (async () =>
    new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 })) as unknown as typeof fetch;
  const result = await new ApnsClient(config, fakeFetch).send("aa", "sandbox", {});
  assertEquals(result, { status: 400, reason: "BadDeviceToken" });
});

Deno.test("classify separates dead tokens from retryable failures", () => {
  assertEquals(classify({ status: 200 }), "accepted");
  assertEquals(classify({ status: 410, reason: "Unregistered" }), "invalid_token");
  assertEquals(classify({ status: 400, reason: "BadDeviceToken" }), "invalid_token");
  assertEquals(classify({ status: 400, reason: "DeviceTokenNotForTopic" }), "invalid_token");
  assertEquals(classify({ status: 400, reason: "PayloadTooLarge" }), "failed");
  assertEquals(classify({ status: 403, reason: "ExpiredProviderToken" }), "failed");
  assertEquals(classify({ status: 429, reason: "TooManyRequests" }), "failed");
  assertEquals(classify({ status: 503 }), "failed");
});
