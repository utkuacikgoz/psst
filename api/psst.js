// psstapp.fun/p/CODE: a Psst that is the invite (owner pick 5A, 14 Oct 2026).
// "Utku pssted you." with Apple's Smart App Banner and one button to get Psst.
// Reads only the inviter's first name and the link's state (public_invite_card).
// Needs PSST_SUPABASE_URL and PSST_SUPABASE_ANON_KEY in Vercel's environment;
// without them, or if anything fails, it shows the same page without the name.
// Shared code lookup and preview tags live in _lib/invite-card.js.

const { SITE, cleanCode, escape, fetchCard, firstName, cardImageURL, previewMeta } = require("./_lib/invite-card");

const STORE = "https://apps.apple.com/app/apple-store/id6815764359?pt=129413467&ct=psst-invite&mt=8";

function page(code, info) {
  const pending = info && info.status === "pending" && info.kind === "psst";
  const gone = info && !pending;
  const name = pending ? firstName(info, "psst") : null;
  const who = name ? escape(name) : "Someone";
  const expires = pending && info.expires_at
    ? new Date(info.expires_at).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    : null;
  const title = gone ? "This Psst has been opened" : `${who} pssted you`;
  const link = SITE + "/p/" + code;
  // Link previews (owner pick 4A): the first name in the title and a per-link card.
  const meta = previewMeta({
    title: gone ? title : name ? `${name} pssted you · 1 Psst waiting` : "Someone pssted you",
    description: `Open it to see, and psst ${name ? "them" : "back"}.`,
    url: link,
    image: name ? cardImageURL(code, "p") : SITE + "/img/home.webp",
  });
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#AC3E68">
<meta name="apple-itunes-app" content="app-id=6815764359, app-argument=${escape(link)}">
${meta}
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>${title}</title>
<link rel="stylesheet" href="/style.css">
<style>
  body.invite { background: var(--pink); color: #fff; min-height: 100vh; }
  .invite main { max-width: 560px; margin: 0 auto; padding: 32px 24px 64px; }
  .invite .wordmark { color: #fff; }
  body.invite h1 { font: 900 clamp(46px, 11vw, 76px)/.98 var(--display); letter-spacing: -.045em; color: #fff; margin: 40px 0 18px; }
  .invite p { font-size: 19px; line-height: 1.5; font-weight: 600; margin: 0 0 18px; }
  .sealed { display: flex; gap: 16px; align-items: center; background: rgba(0,0,0,.16); border-radius: 22px; padding: 18px 20px; margin: 26px 0 0; }
  .sealed svg { flex: none; }
  .sealed b { display: block; font: 800 19px var(--display); }
  .sealed span { font-size: 15px; font-weight: 600; opacity: .9; }
  .btn { display: block; text-align: center; background: var(--ink); color: #fff; text-decoration: none; font: 800 18px var(--display); padding: 18px; border-radius: 16px; margin-top: 26px; }
  .small { font-size: 14px; opacity: .85; font-weight: 500; text-align: center; }
  .small a { color: #fff; }
</style>
</head>
<body class="invite">
<main>
  <a class="wordmark" href="/">psst</a>
  <h1>${gone ? "This Psst has been opened." : `${who} pssted you.`}</h1>
  <p>${gone
    ? "Each one is for one person and lasts a week. Ask them to psst you again, or get Psst and invite them."
    : "Psst is a tiny app for the people you're close to: one tap says <em>thinking of you</em>."}</p>
  ${gone ? "" : `<div class="sealed">
    <svg width="44" height="40" viewBox="0 0 100 90" aria-hidden="true"><path fill="#fff" d="M12 86 Q1 55 15 30 L13 5 L38 24 Q52 17 65 24 L88 4 L86 33 Q99 55 88 86 Z"/><g fill="none" stroke="#AC3E68" stroke-width="7" stroke-linecap="round"><path d="M27 48 L40 53"/><path d="M61 52 Q70 44 75 47"/><path d="M45 66 L52 72 L59 66"/></g></svg>
    <div><b>1 Psst from ${who}</b><span>Waiting for you in the app</span></div>
  </div>`}
  <a class="btn" id="get" href="${STORE}" data-code="${escape(code)}">${gone ? "Get Psst" : "Get Psst to open it"}</a>
  <p class="small" style="margin-top:12px">Already have it? <a href="psst://invite/${escape(code)}">Open in Psst</a></p>
  <p class="small" style="margin-top:22px">${expires ? `This link is for one person · expires ${escape(expires)}` : "This link is for one person and lasts a week."}
    <br><a href="/privacy">Privacy</a> · <a href="/support">Support</a></p>
</main>
<script src="/psst.js"></script>
</body></html>`;
}

module.exports = async (req, res) => {
  const code = cleanCode(req.query && req.query.code);
  const info = await fetchCard(code);
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "private, no-store");
  res.status(200).send(page(code, info));
};

module.exports.page = page;
