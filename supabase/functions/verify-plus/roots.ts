/**
 * Apple's root certificates as base64, comma-separated. Also accepts the older
 * JSON list, including the double-escaped form earlier deploys stored.
 */
export function parseRoots(value: string): string[] {
  return value.replace(/[\[\]"\\\s]/g, "").split(",").filter(Boolean);
}
