import { createClient } from "jsr:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Deletes the caller's auth user. Foreign keys cascade to the profile,
// connections, signals, invites and device tokens.
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization");
  if (!authorization) return json({ error: "not_authenticated" }, 401);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await caller.auth.getUser();
  if (error || !user) return json({ error: "not_authenticated" }, 401);

  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { error: deleteError } = await service.auth.admin.deleteUser(user.id);
  if (deleteError) return json({ error: "delete_failed" }, 500);
  return new Response(null, { status: 204 });
});
