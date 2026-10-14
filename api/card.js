// psstapp.fun/api/card?code=CODE: the inviter's first name for the invite page
// (owner pick 6A, 14 Oct 2026). Same source as /p/ (public_invite_card): only a
// first name, and only while the code can still be used. Needs PSST_SUPABASE_URL
// and PSST_SUPABASE_ANON_KEY in Vercel; without them it answers {} and the page
// keeps "Someone wants to psst you."

module.exports = async (req, res) => {
  const code = String((req.query && req.query.code) || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 16);
  const base = process.env.PSST_SUPABASE_URL;
  const key = process.env.PSST_SUPABASE_ANON_KEY;
  let name = null;
  if (code && base && key) {
    try {
      const response = await fetch(base.replace(/\/$/, "") + "/rest/v1/rpc/public_invite_card", {
        method: "POST",
        headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
        body: JSON.stringify({ p_code: code }),
        signal: AbortSignal.timeout(3000),
      });
      const info = response.ok ? await response.json() : null;
      if (info && info.status === "pending" && typeof info.first_name === "string") {
        name = info.first_name.trim().slice(0, 40) || null;
      }
    } catch {
      name = null;
    }
  }
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "private, no-store");
  res.status(200).send(JSON.stringify(name ? { first_name: name } : {}));
};
