// Apple Push Notification service over HTTP/2 with token (.p8) authentication.
// Hosts, paths and status handling follow Apple's "Sending notification requests
// to APNs". Provider tokens are reused for 50 minutes: Apple rejects tokens older
// than an hour and throttles regeneration more often than every 20 minutes.

export type ApnsEnvironment = "sandbox" | "production";

export interface ApnsConfig {
  teamId: string;
  keyId: string;
  /** Contents of the .p8 file (PKCS#8 PEM). Server secret; never logged. */
  privateKeyPem: string;
  /** apns-topic: the app's bundle identifier. */
  bundleId: string;
}

export interface ApnsResult {
  status: number;
  reason?: string;
}

export type ApnsOutcome = "accepted" | "invalid_token" | "failed";

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

const TOKEN_LIFETIME_SECONDS = 50 * 60;

/** Reasons that mean this token will never work again for this app. */
const INVALID_TOKEN_REASONS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"]);

export function classify(result: ApnsResult): ApnsOutcome {
  if (result.status === 200) return "accepted";
  if (result.status === 410) return "invalid_token";
  if (result.status === 400 && result.reason && INVALID_TOKEN_REASONS.has(result.reason)) {
    return "invalid_token";
  }
  return "failed";
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export async function createProviderToken(config: ApnsConfig, issuedAt: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKeyPem).buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: config.teamId, iat: issuedAt })));
  const signingInput = `${header}.${claims}`;
  // WebCrypto returns the raw r||s signature, which is what JWS ES256 expects.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

export class ApnsClient {
  private cached?: { token: string; issuedAt: number };

  constructor(
    private readonly config: ApnsConfig,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly nowSeconds: () => number = () => Math.floor(Date.now() / 1000),
  ) {}

  private async providerToken(): Promise<string> {
    const now = this.nowSeconds();
    if (!this.cached || now - this.cached.issuedAt >= TOKEN_LIFETIME_SECONDS) {
      this.cached = { token: await createProviderToken(this.config, now), issuedAt: now };
    }
    return this.cached.token;
  }

  async send(
    deviceToken: string,
    environment: ApnsEnvironment,
    payload: unknown,
    options: { apnsId?: string; expiresAt?: number; collapseId?: string } = {},
  ): Promise<ApnsResult> {
    const headers: Record<string, string> = {
      "authorization": `bearer ${await this.providerToken()}`,
      "apns-push-type": "alert",
      "apns-topic": this.config.bundleId,
      "apns-priority": "10",
      "content-type": "application/json",
    };
    if (options.apnsId) headers["apns-id"] = options.apnsId;
    if (options.expiresAt !== undefined) headers["apns-expiration"] = String(options.expiresAt);
    if (options.collapseId) headers["apns-collapse-id"] = options.collapseId;

    const response = await this.fetchImpl(`${HOSTS[environment]}/3/device/${deviceToken}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });
    if (response.status === 200) {
      await response.body?.cancel();
      return { status: 200 };
    }
    let reason: string | undefined;
    try {
      reason = (await response.json())?.reason;
    } catch {
      reason = undefined;
    }
    return { status: response.status, reason };
  }
}
