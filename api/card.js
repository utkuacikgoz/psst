// psstapp.fun/api/card?code=CODE: the inviter's first name for the invite page
// (owner pick 6A, 14 Oct 2026). Same source as /p/ (public_invite_card): only a
// first name, and only while the code can still be used. Needs PSST_SUPABASE_URL
// and PSST_SUPABASE_ANON_KEY in Vercel; without them it answers {} and the page
// keeps "Someone wants to psst you."
//
// With &image=p or &image=invite it answers the link-preview card instead
// (owner pick 4A): a 1200x630 PNG, "<Name> pssted you" + "1 Psst waiting" for
// /p/ links, "<Name> invited you" for /invite/ codes; "Someone" when the name
// isn't known. The name always comes from the server, never from the URL.

const { cleanCode, fetchCard, firstName } = require("./_lib/invite-card");
const { renderCard } = require("./_card/render");

module.exports = async (req, res) => {
  const query = req.query || {};
  const code = cleanCode(query.code);
  const image = query.image === "p" || query.image === "invite" ? query.image : null;
  const info = await fetchCard(code);

  if (image) {
    // /p/ only names the sender of a waiting Psst (same rule as api/psst.js).
    const name = firstName(info, image === "p" ? "psst" : null);
    let body;
    try {
      body = renderCard(name, image);
    } catch {
      res.statusCode = 302;
      res.setHeader("Location", "/img/home.webp");
      res.setHeader("Cache-Control", "public, max-age=300");
      return res.end();
    }
    res.setHeader("Content-Type", "image/png");
    res.setHeader("Cache-Control", "public, max-age=300");
    return res.status(200).send(body);
  }

  const name = firstName(info);
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "private, no-store");
  res.status(200).send(JSON.stringify(name ? { first_name: name } : {}));
};
