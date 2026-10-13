import { assertEquals } from "jsr:@std/assert@1";
import { handleVerifyPlus, VerifyPlusDeps } from "../verify-plus/handler.ts";
const user = "11111111-1111-4111-8111-111111111111";
function request(body: unknown = {signed_transaction:"header.payload.signature"}) {
  return new Request("https://example.test", {method:"POST",headers:{authorization:"Bearer caller"},body:JSON.stringify(body)});
}
function deps(overrides: Partial<VerifyPlusDeps> = {}): VerifyPlusDeps {
  return {authenticate:()=>Promise.resolve(user),verify:()=>Promise.resolve({originalTransactionId:"tx",active:true}),record:()=>Promise.resolve(),...overrides};
}
Deno.test("proof must verify before a server entitlement is written", async()=> {
  let writes=0;
  assertEquals((await handleVerifyPlus(request(),deps({verify:()=>Promise.reject(new Error("bad signature")),record:()=>{writes++;return Promise.resolve();}}))).status,503);
  assertEquals(writes,0);
});
Deno.test("a restore on a new account takes the purchase over",async()=> {
  let recordedFor="";
  const response=await handleVerifyPlus(request(),deps({verify:()=>Promise.resolve({originalTransactionId:"tx",active:true,appAccountToken:"old-account"}),record:(id)=>{recordedFor=id;return Promise.resolve();}}));
  assertEquals(response.status,204);assertEquals(recordedFor,user);
});
Deno.test("a recently verified account skips Apple",async()=> {
  let asked=0;
  const response=await handleVerifyPlus(request(),deps({isCurrent:()=>Promise.resolve(true),verify:()=>{asked++;return Promise.resolve({originalTransactionId:"tx",active:true});}}));
  assertEquals(response.status,204);assertEquals(asked,0);
});
Deno.test("revocation is recorded before refusing unlock",async()=> {
  let active=true;
  assertEquals((await handleVerifyPlus(request(),deps({verify:()=>Promise.resolve({originalTransactionId:"tx",active:false}),record:(_user,purchase)=>{active=purchase.active;return Promise.resolve();}}))).status,403);
  assertEquals(active,false);
});
Deno.test("a valid purchase unlocks; a failed write is temporary, not a conflict",async()=> {
  assertEquals((await handleVerifyPlus(request(),deps())).status,204);
  assertEquals((await handleVerifyPlus(request(),deps({record:()=>Promise.reject(new Error("db down"))}))).status,503);
});
Deno.test("unauthenticated or malformed requests cannot verify or unlock",async()=> {
  assertEquals((await handleVerifyPlus(request(),deps({authenticate:()=>Promise.resolve(null)}))).status,401);
  assertEquals((await handleVerifyPlus(request({signed_transaction:true}),deps())).status,400);
});
