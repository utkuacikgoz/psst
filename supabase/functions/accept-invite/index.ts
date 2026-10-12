import { createClient } from "jsr:@supabase/supabase-js@2";
import { ApnsClient } from "../_shared/apns.ts";
import { handleAcceptInvite } from "./handler.ts";

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
  handleAcceptInvite(req, {
    async acceptInvite(authorization, code) {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false },
      });
      const { data, error, status } = await caller.rpc("accept_invite", { p_code: code });
      return { data, error, status };
    },
    async joinedTargets(connectionId) {
      const { data, error } = await service.rpc("joined_push_targets", { p_connection_id: connectionId });
      if (error) throw new Error(error.message);
      return data;
    },
    async removeTokens(tokens) {
      const { error } = await service.rpc("remove_device_tokens", { p_tokens: tokens });
      if (error) throw new Error(error.message);
    },
    sendPush: (token, environment, payload, options) => apns.send(token, environment, payload, options),
    nowSeconds: () => Math.floor(Date.now() / 1000),
  })
);
