import { createClient } from "jsr:@supabase/supabase-js@2";
import { ApnsClient } from "../_shared/apns.ts";
import { deliver } from "../_shared/deliver.ts";
import { handleSendSignal } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const service = createClient(url, serviceKey, { auth: { persistSession: false } });

const apns = new ApnsClient({
  teamId: Deno.env.get("APNS_TEAM_ID")!,
  keyId: Deno.env.get("APNS_KEY_ID")!,
  privateKeyPem: Deno.env.get("APNS_PRIVATE_KEY")!,
  bundleId: Deno.env.get("APNS_BUNDLE_ID")!,
});

Deno.serve((req) =>
  handleSendSignal(req, {
    async sendSignal(authorization, args) {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false },
      });
      const { data, error, status } = await caller.rpc("send_signal", args);
      return { data, error, status };
    },
    deliver: (eventId) =>
      deliver(eventId, {
        async pushTargets(id) {
          const { data, error } = await service.rpc("push_targets", { p_event_id: id });
          if (error) throw new Error(error.message);
          return data;
        },
        async recordPushResult(id, status, invalidTokens) {
          const { error } = await service.rpc("record_push_result", {
            p_event_id: id,
            p_status: status,
            p_invalid_tokens: invalidTokens,
          });
          if (error) throw new Error(error.message);
        },
        sendPush: (token, environment, payload, options) => apns.send(token, environment, payload, options),
        nowSeconds: () => Math.floor(Date.now() / 1000),
      }),
  })
);
