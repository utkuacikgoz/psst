// Runs Apple's own online certificate check (as verify-plus does in production)
// on Apple's real intermediate, to show whether it works from a server.
import { Buffer } from "node:buffer";
import { X509Certificate } from "node:crypto";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";

const download = async (url: string) => Buffer.from(await (await fetch(url)).arrayBuffer());
const root = await download("https://www.apple.com/certificateauthority/AppleRootCA-G3.cer");
const intermediate = await download("https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer");
// deno-lint-ignore no-explicit-any
const verifier: any = new SignedDataVerifier([root], true, Environment.PRODUCTION, "check", 1);
try {
  await verifier.checkOCSPStatus(new X509Certificate(intermediate), new X509Certificate(root));
  console.log("Apple certificate status check: OK");
} catch (error) {
  // deno-lint-ignore no-explicit-any
  const e = error as any;
  console.log("Apple certificate status check FAILED:", e?.name, e?.message, e?.status ?? "");
  Deno.exit(1);
}
