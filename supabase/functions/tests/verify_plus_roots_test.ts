import { assertEquals } from "jsr:@std/assert@1";
import { parseRoots } from "../verify-plus/roots.ts";

Deno.test("roots: plain, JSON and the double-escaped form earlier deploys stored", () => {
  assertEquals(parseRoots("MIICQzCC+/="), ["MIICQzCC+/="]);
  assertEquals(parseRoots('["MIICQzCC","MIIB"]'), ["MIICQzCC", "MIIB"]);
  assertEquals(parseRoots('[\\"MIICQzCC\\"]'), ["MIICQzCC"]);
  assertEquals(parseRoots(""), []);
});
