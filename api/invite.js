// psstapp.fun/invite/CODE: the group invite page, rendered here so link
// previews (Messages, WhatsApp) can show who it's from (owner pick 4A): the
// og:/twitter: tags carry "Utku invited you to Psst" and a per-link card, and
// the name is filled in before the page loads. The page itself is
// site/invite.html, unchanged; only its head tags, title and heading text are
// swapped. invite.js still runs as before. Needs PSST_SUPABASE_URL and
// PSST_SUPABASE_ANON_KEY; without them it serves the page as it was.

const fs = require("fs");
const path = require("path");
const { SITE, cleanCode, escape, fetchCard, firstName, cardImageURL, previewMeta } = require("./_lib/invite-card");

const TEMPLATE = path.join(__dirname, "..", "site", "invite.html");
let template = null;

// Exact snippets of site/invite.html this replaces. If one is missing (the page
// changed), that part stays as the static page has it.
const DESCRIPTION = '<meta name="description" content="Someone wants to psst you. Get Psst and connect with one code.">';
const BANNER = '<meta name="apple-itunes-app" content="app-id=6815764359">';
const PREVIEW = /<meta property="og:title"[^>]*>\n<meta property="og:description"[^>]*>\n<meta property="og:image"[^>]*>/;
const TITLE = "<title>You're invited to Psst</title>";
const HEADING = "<h1>Someone wants to psst you.</h1>";
const GENERIC_DESCRIPTION = "Tap to connect on Psst: one tap says thinking of you.";

function page(html, code, info) {
  const name = firstName(info);
  const who = name ? escape(name) : null;
  const link = SITE + "/invite/" + code;
  let out = html;
  if (code) {
    out = out.replace(BANNER, () => `<meta name="apple-itunes-app" content="app-id=6815764359, app-argument=${escape(link)}">`);
  }
  out = out.replace(PREVIEW, () => previewMeta({
    title: name ? `${name} invited you to Psst` : "Someone wants to psst you",
    description: GENERIC_DESCRIPTION,
    url: code ? link : SITE + "/invite",
    image: name ? cardImageURL(code, "invite") : SITE + "/img/home.webp",
  }));
  if (who) {
    out = out
      .replace(DESCRIPTION, () => `<meta name="description" content="${who} wants to psst you. Get Psst and connect with one code.">`)
      .replace(TITLE, () => `<title>${who} wants to psst you</title>`)
      .replace(HEADING, () => `<h1>${who} wants to psst you.</h1>`);
  }
  return out;
}

module.exports = async (req, res) => {
  const code = cleanCode(req.query && req.query.code);
  try {
    template = template || fs.readFileSync(TEMPLATE, "utf8");
  } catch {
    res.statusCode = 500;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    return res.end("Something went wrong. Try the link again in a moment.");
  }
  const info = await fetchCard(code);
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "private, no-store");
  res.status(200).send(page(template, code, info));
};

module.exports.page = page;
