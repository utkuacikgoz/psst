// Shared by /p/CODE (api/psst.js), /invite/CODE (api/invite.js) and the card
// image (api/card.js): one way to clean a code, read public_invite_card and
// pick a safe first name. Files under api/_lib are not served by Vercel.
// Needs PSST_SUPABASE_URL and PSST_SUPABASE_ANON_KEY; without them every
// lookup answers null and the pages fall back to "Someone".

const SITE = "https://psstapp.fun";

function cleanCode(raw) {
  return String(raw || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 16);
}

function escape(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function fetchCard(code) {
  const base = process.env.PSST_SUPABASE_URL;
  const key = process.env.PSST_SUPABASE_ANON_KEY;
  if (!code || !base || !key) return null;
  try {
    const response = await fetch(base.replace(/\/$/, "") + "/rest/v1/rpc/public_invite_card", {
      method: "POST",
      headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({ p_code: code }),
      signal: AbortSignal.timeout(3000),
    });
    const info = response.ok ? await response.json() : null;
    return info && typeof info === "object" ? info : null;
  } catch {
    return null;
  }
}

// The inviter's first name while the code can still be used, or null. `kind`
// narrows it to one kind of link ("psst" for /p/). Control characters go, and
// it is cut to 40 characters (whole characters, not UTF-16 halves).
function firstName(info, kind) {
  if (!info || info.status !== "pending" || (kind && info.kind !== kind)) return null;
  if (typeof info.first_name !== "string") return null;
  const name = Array.from(info.first_name.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2066-\u2069]/g, "").trim())
    .slice(0, 40).join("").trim();
  return name || null;
}

// The per-link preview image (api/card.js?image=p|invite).
function cardImageURL(code, image) {
  return `${SITE}/api/card?code=${encodeURIComponent(code)}&image=${image}`;
}

// og: and twitter: tags for a link preview. Everything is escaped here.
function previewMeta({ title, description, url, image }) {
  const big = image && image !== `${SITE}/img/home.webp`;
  return [
    `<meta property="og:type" content="website">`,
    `<meta property="og:url" content="${escape(url)}">`,
    `<meta property="og:title" content="${escape(title)}">`,
    `<meta property="og:description" content="${escape(description)}">`,
    `<meta property="og:image" content="${escape(image)}">`,
    ...(big ? [`<meta property="og:image:width" content="1200">`, `<meta property="og:image:height" content="630">`,
               `<meta property="og:image:type" content="image/png">`] : []),
    `<meta name="twitter:card" content="${big ? "summary_large_image" : "summary"}">`,
    `<meta name="twitter:title" content="${escape(title)}">`,
    `<meta name="twitter:description" content="${escape(description)}">`,
    `<meta name="twitter:image" content="${escape(image)}">`,
  ].join("\n");
}

module.exports = { SITE, cleanCode, escape, fetchCard, firstName, cardImageURL, previewMeta };
