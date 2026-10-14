import { createClient } from "jsr:@supabase/supabase-js@2";
import { ApnsClient } from "../_shared/apns.ts";
import { handleWeeklyRecap, RecapTarget } from "./handler.ts";

const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const apns = new ApnsClient({
  teamId: Deno.env.get("APNS_TEAM_ID")!,
  keyId: Deno.env.get("APNS_KEY_ID")!,
  privateKeyPem: Deno.env.get("APNS_PRIVATE_KEY")!,
  bundleId: Deno.env.get("APNS_BUNDLE_ID")!,
});

Deno.serve((req) =>
  handleWeeklyRecap(req, {
    async cronOk(secret) {
      const { data, error } = await service.rpc("recap_cron_ok", { p_secret: secret });
      return !error && data === true;
    },
    async targets() {
      const { data, error } = await service.rpc("recap_push_targets");
      if (error) throw new Error(error.message);
      return (data ?? []) as RecapTarget[];
    },
    async removeTokens(tokens) {
      const { error } = await service.rpc("remove_device_tokens", { p_tokens: tokens });
      if (error) throw new Error(error.message);
    },
    sendPush: (token, environment, payload, options) => apns.send(token, environment, payload, options),
    nowSeconds: () => Math.floor(Date.now() / 1000),
    newId: () => crypto.randomUUID(),
  })
);
