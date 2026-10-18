// Link previews (owner pick 4A) for /p/CODE, /invite/CODE and the card image,
// with a fake Supabase. Run: node --test api/_test/link-previews.test.js
// (Files under api/_test are not deployed as functions.)

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

process.env.PSST_SUPABASE_URL = "https://example.supabase.co/";
process.env.PSST_SUPABASE_ANON_KEY = "test-anon-key";

const psst = require("../psst");
const invite = require("../invite");
const card = require("../card");

let calls = [];
let answer = null; // what the fake RPC returns; a function gets the code
globalThis.fetch = async (url, options) => {
  const body = JSON.parse(options.body);
  calls.push({ url, body, headers: options.headers });
  const value = typeof answer === "function" ? answer(body.p_code) : answer;
  if (value instanceof Error) throw value;
  if (value === 500) return { ok: false, json: async () => ({}) };
  return { ok: true, json: async () => value };
};

function call(handler, query) {
  return new Promise((resolve, reject) => {
    const res = {
      statusCode: 200, headers: {},
      setHeader(k, v) { this.headers[k.toLowerCase()] = v; },
      status(code) { this.statusCode = code; return this; },
      send(body) { resolve({ status: this.statusCode, headers: this.headers, body }); },
      end(body) { resolve({ status: this.statusCode, headers: this.headers, body }); },
    };
    Promise.resolve(handler({ query }, res)).catch(reject);
  });
}

function meta(html, key) {
  const m = html.match(new RegExp(`<meta (?:property|name)="${key}" content="([^"]*)">`));
  return m && m[1];
}

const pending = (first_name, kind = "psst") => ({ status: "pending", kind, first_name, expires_at: "2026-10-25T10:00:00Z" });

test.beforeEach(() => { calls = []; answer = null; });

test("/p/: name in og:title, per-link card image, twitter tags", async () => {
  answer = pending("Utku");
  const r = await call(psst, { code: "ab12cd34" });
  assert.equal(r.status, 200);
  assert.equal(calls[0].url, "https://example.supabase.co/rest/v1/rpc/public_invite_card");
  assert.deepEqual(calls[0].body, { p_code: "AB12CD34" });
  assert.equal(meta(r.body, "og:title"), "Utku pssted you · 1 Psst waiting");
  assert.equal(meta(r.body, "twitter:title"), "Utku pssted you · 1 Psst waiting");
  assert.equal(meta(r.body, "og:image"), "https://psstapp.fun/api/card?code=AB12CD34&amp;image=p");
  assert.equal(meta(r.body, "twitter:card"), "summary_large_image");
  assert.equal(meta(r.body, "og:url"), "https://psstapp.fun/p/AB12CD34");
  assert.match(r.body, /<h1>Utku pssted you\.<\/h1>/);
  assert.match(r.body, /<title>Utku pssted you<\/title>/);
});

test("/p/: falls back to today's generic text", async () => {
  for (const value of [null, 500, new Error("down"), pending(""), pending("Utku", "invite")]) {
    answer = value;
    const r = await call(psst, { code: "AB12CD34" });
    assert.equal(r.status, 200);
    if (value && value.kind === "invite") {
      assert.equal(meta(r.body, "og:title"), "This Psst has been opened");
    } else {
      assert.equal(meta(r.body, "og:title"), "Someone pssted you", String(value));
      assert.match(r.body, /<h1>Someone pssted you\.<\/h1>/);
    }
    assert.equal(meta(r.body, "og:image"), "https://psstapp.fun/img/home.webp");
  }
  answer = { status: "unavailable" };
  const r = await call(psst, { code: "AB12CD34" });
  assert.equal(meta(r.body, "og:title"), "This Psst has been opened");
});

test("/p/: without Vercel env no lookup happens", async () => {
  const saved = process.env.PSST_SUPABASE_URL;
  delete process.env.PSST_SUPABASE_URL;
  answer = pending("Utku");
  const r = await call(psst, { code: "AB12CD34" });
  process.env.PSST_SUPABASE_URL = saved;
  assert.equal(calls.length, 0);
  assert.equal(meta(r.body, "og:title"), "Someone pssted you");
});

test("names are escaped everywhere", async () => {
  const evil = `<script>"x'&`;
  answer = pending(evil);
  const p = await call(psst, { code: "AB12CD34" });
  answer = pending(evil, "invite");
  const i = await call(invite, { code: "AB12CD34" });
  for (const html of [p.body, i.body]) {
    assert.ok(!html.includes("<script>\""), "raw name leaked");
    assert.ok(html.includes("&lt;script&gt;&quot;x&#39;&amp;"));
  }
  assert.equal(meta(i.body, "og:title"), "&lt;script&gt;&quot;x&#39;&amp; invited you to Psst");
});

test("control characters are dropped and names cut to 40 characters", async () => {
  answer = pending("Ut\u0000ku\u202e" + "é".repeat(60));
  const r = await call(card, { code: "AB12CD34" });
  const name = JSON.parse(r.body).first_name;
  assert.equal(Array.from(name).length, 40);
  assert.ok(name.startsWith("Utku"));
});

test("code validation is as strict as before", async () => {
  answer = pending("Utku");
  const r = await call(invite, { code: "ab-12/../cd34<x>\"" + "Z".repeat(30) });
  assert.equal(calls[0].body.p_code, "AB12CD34X" + "Z".repeat(7));
  assert.equal(calls[0].body.p_code.length, 16);
  assert.ok(!r.body.includes("<x>"));
  calls = [];
  const empty = await call(invite, { code: "!!!" });
  assert.equal(calls.length, 0, "no lookup for an empty code");
  assert.match(empty.body, /<meta name="apple-itunes-app" content="app-id=6815764359">/);
  assert.equal(meta(empty.body, "og:title"), "Someone wants to psst you");
  calls = [];
  await call(psst, { code: undefined });
  assert.equal(calls.length, 0);
});

test("/invite/: same page as site/invite.html with the name and head tags filled", async () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "..", "site", "invite.html"), "utf8");
  answer = pending("Utku", "invite");
  const r = await call(invite, { code: "ab12cd34" });
  assert.equal(r.status, 200);
  assert.equal(r.headers["content-type"], "text/html; charset=utf-8");
  assert.equal(meta(r.body, "og:title"), "Utku invited you to Psst");
  assert.equal(meta(r.body, "twitter:title"), "Utku invited you to Psst");
  assert.equal(meta(r.body, "og:description"), "Tap to connect on Psst: one tap says thinking of you.");
  assert.equal(meta(r.body, "og:image"), "https://psstapp.fun/api/card?code=AB12CD34&amp;image=invite");
  assert.equal(meta(r.body, "og:url"), "https://psstapp.fun/invite/AB12CD34");
  assert.equal(meta(r.body, "apple-itunes-app"), "app-id=6815764359, app-argument=https://psstapp.fun/invite/AB12CD34");
  assert.match(r.body, /<title>Utku wants to psst you<\/title>/);
  assert.match(r.body, /<h1>Utku wants to psst you\.<\/h1>/);
  assert.match(r.body, /<meta name="description" content="Utku wants to psst you\./);
  // Everything from <body> on is the static page except the heading.
  const body = (s) => s.slice(s.indexOf("<body"));
  assert.equal(body(r.body).replace("<h1>Utku wants", "<h1>Someone wants"), body(html));
  assert.ok(r.body.includes('<script src="/invite.js"></script>'));
});

test("/invite/: falls back to the static page's text", async () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "..", "site", "invite.html"), "utf8");
  for (const value of [null, 500, new Error("down"), { status: "unavailable" }, pending("   ")]) {
    answer = value;
    const r = await call(invite, { code: "AB12CD34" });
    assert.equal(meta(r.body, "og:title"), "Someone wants to psst you");
    assert.equal(meta(r.body, "og:image"), "https://psstapp.fun/img/home.webp");
    assert.equal(meta(r.body, "twitter:card"), "summary");
    assert.ok(r.body.includes("<h1>Someone wants to psst you.</h1>"));
    assert.ok(r.body.includes("<title>You're invited to Psst</title>"));
    assert.equal(r.body.slice(r.body.indexOf("<body")), html.slice(html.indexOf("<body")));
  }
});

test("/invite/: every snippet it replaces is still in site/invite.html", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "..", "site", "invite.html"), "utf8");
  const out = invite.page(html, "AB12CD34", pending("Utku", "invite"));
  assert.ok(!out.includes('content="Someone wants to psst you'), "description or og:title not replaced");
  assert.ok(!out.includes("You're invited to Psst</title>"));
  assert.ok(!out.includes("<h1>Someone"));
  assert.ok(out.includes("app-argument="));
  assert.equal((out.match(/og:image"/g) || []).length, 1);
});

function readPNG(buffer) {
  assert.deepEqual([...buffer.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const width = buffer.readUInt32BE(16), height = buffer.readUInt32BE(20);
  let idat = [], at = 8;
  while (at < buffer.length) {
    const len = buffer.readUInt32BE(at), type = buffer.toString("latin1", at + 4, at + 8);
    if (type === "IDAT") idat.push(buffer.subarray(at + 8, at + 8 + len));
    at += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const pixel = (x, y) => [...raw.subarray(y * (width * 3 + 1) + 1 + x * 3, y * (width * 3 + 1) + 1 + x * 3 + 3)];
  return { width, height, pixel, raw };
}

test("card image: 1200x630 PNG, pink, white text, cached 5 minutes", async () => {
  answer = pending("Utku");
  const r = await call(card, { code: "AB12CD34", image: "p" });
  assert.equal(r.status, 200);
  assert.equal(r.headers["content-type"], "image/png");
  assert.equal(r.headers["cache-control"], "public, max-age=300");
  const png = readPNG(r.body);
  assert.equal(png.width, 1200);
  assert.equal(png.height, 630);
  assert.deepEqual(png.pixel(5, 5), [0xC2, 0x18, 0x5B]);
  let white = 0;
  for (let i = 1; i < png.raw.length - 2; i += 3) if (png.raw[i] === 255 && png.raw[i + 1] === 255 && png.raw[i + 2] === 255) white++;
  assert.ok(white > 20000, "text drawn");
});

test("card image: name comes from the server; differs per name and kind", async () => {
  answer = pending("Utku");
  const a = await call(card, { code: "AB12CD34", image: "p", name: "Hacker" });
  answer = pending("Mia");
  const b = await call(card, { code: "AB12CD34", image: "p" });
  answer = pending("Mia", "invite");
  const c = await call(card, { code: "AB12CD34", image: "invite" });
  answer = pending("Mia", "invite");
  const d = await call(card, { code: "AB12CD34", image: "p" }); // not a Psst link: "Someone"
  answer = null;
  const e = await call(card, { code: "AB12CD34", image: "p" });
  assert.notDeepEqual(a.body, b.body);
  assert.notDeepEqual(b.body, c.body);
  assert.deepEqual(d.body, e.body);
  answer = pending("日本");
  const f = await call(card, { code: "AB12CD34", image: "p" }); // no glyphs: "Someone"
  assert.deepEqual(f.body, e.body);
});

test("card JSON for invite.js is unchanged", async () => {
  answer = pending("  Lily  ", "invite");
  const r = await call(card, { code: "AB12CD34" });
  assert.equal(r.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(r.headers["cache-control"], "private, no-store");
  assert.deepEqual(JSON.parse(r.body), { first_name: "Lily" });
  answer = { status: "unavailable" };
  assert.deepEqual(JSON.parse((await call(card, { code: "AB12CD34" })).body), {});
  const bad = await call(card, { code: "AB12CD34", image: "<svg>" });
  assert.equal(bad.headers["content-type"], "application/json; charset=utf-8");
});

// Doodle Psst links (owner picks 2A 3A, 18 Oct 2026).
const doodle = (first_name) => ({ ...pending(first_name), doodle: true });

test("/p/ doodle: heading, sealed polaroid, box, button and preview", async () => {
  answer = doodle("Utku");
  const r = await call(psst, { code: "AB12CD34" });
  assert.match(r.body, /<h1>Utku drew you something\.<\/h1>/);
  assert.match(r.body, /<title>Utku drew you something<\/title>/);
  assert.match(r.body, /<b>1 doodle from Utku<\/b><span>Waiting for you in the app<\/span>/);
  assert.match(r.body, /<a class="btn" id="get" href="[^"]+" data-code="AB12CD34">GET PSST TO SEE IT<\/a>/);
  assert.ok(r.body.indexOf('class="polaroid"') < r.body.indexOf('class="sealed"'), "polaroid above the waiting box");
  assert.match(r.body, /<span class="sticker">SEALED ✎<\/span>/);
  assert.match(r.body, /<div class="from">from Utku<\/div>/);
  assert.equal(meta(r.body, "og:title"), "Utku drew you something");
  assert.equal(meta(r.body, "twitter:title"), "Utku drew you something");
  assert.equal(meta(r.body, "og:image"), "https://psstapp.fun/api/card?code=AB12CD34&amp;image=doodle");
  assert.equal(meta(r.body, "twitter:card"), "summary_large_image");
});

test("/p/ doodle: the polaroid carries no strokes or drawing data", async () => {
  answer = { ...doodle("Utku"), strokes: [[{ x: 1, y: 2 }]], drawing: "SECRET-STROKES" };
  const r = await call(psst, { code: "AB12CD34" });
  const polaroid = r.body.slice(r.body.indexOf('<div class="polaroid"'), r.body.indexOf('<div class="sealed"'));
  assert.ok(polaroid.length > 0);
  assert.ok(!/<svg|<img|<canvas|<path|data-|url\(/.test(polaroid), polaroid);
  assert.ok(!r.body.includes("SECRET-STROKES") && !r.body.includes("strokes"));
});

test("/p/ doodle: falls back to Someone, and escapes the name", async () => {
  answer = doodle("");
  let r = await call(psst, { code: "AB12CD34" });
  assert.match(r.body, /<h1>Someone drew you something\.<\/h1>/);
  assert.match(r.body, /<b>1 doodle from Someone<\/b>/);
  assert.equal(meta(r.body, "og:title"), "Someone drew you something");
  answer = doodle(`<i>"x'`);
  r = await call(psst, { code: "AB12CD34" });
  assert.ok(!r.body.includes("<i>\""));
  assert.match(r.body, /from &lt;i&gt;&quot;x&#39;<\/div>/);
  assert.equal(meta(r.body, "og:title"), "&lt;i&gt;&quot;x&#39; drew you something");
});

test("/p/ doodle flag only counts as exactly true on a waiting Psst link", async () => {
  for (const value of [pending("Utku"), { ...pending("Utku"), doodle: false }, { ...pending("Utku"), doodle: "true" }]) {
    answer = value;
    const r = await call(psst, { code: "AB12CD34" });
    assert.match(r.body, /<h1>Utku pssted you\.<\/h1>/);
    assert.match(r.body, /<b>1 Psst from Utku<\/b>/);
    assert.match(r.body, />Get Psst to open it<\/a>/);
    assert.ok(!r.body.includes("polaroid"));
    assert.equal(meta(r.body, "og:title"), "Utku pssted you · 1 Psst waiting");
  }
  answer = { status: "unavailable", doodle: true };
  const gone = await call(psst, { code: "AB12CD34" });
  assert.ok(!gone.body.includes("polaroid"));
  assert.match(gone.body, /This Psst has been opened\./);
});

test("/p/ without a doodle is unchanged by the doodle work", () => {
  const page = psst.page("AB12CD34", { ...pending("Utku"), doodle: false });
  assert.equal(page, psst.page("AB12CD34", pending("Utku")));
  assert.ok(!page.includes(".polaroid") && !page.includes("SEALED") && !page.includes("drew you"));
});

test("card image: doodle variant is a 1200x630 pink PNG, name from the server", async () => {
  answer = doodle("Utku");
  const r = await call(card, { code: "AB12CD34", image: "doodle", name: "Hacker" });
  assert.equal(r.status, 200);
  assert.equal(r.headers["content-type"], "image/png");
  assert.equal(r.headers["cache-control"], "public, max-age=300");
  const png = readPNG(r.body);
  assert.equal(png.width, 1200);
  assert.equal(png.height, 630);
  assert.deepEqual(png.pixel(5, 5), [0xC2, 0x18, 0x5B]);
  const [fr, fg, fb] = png.pixel(960, 400); // frosted square: light pink, not strokes
  assert.ok(fr > 200 && fg > 100 && fg < 200 && fb > 130, `frosted pink, got ${[fr, fg, fb]}`);
  const [r0, g0, b0] = png.pixel(905, 160); // the frame's cream near its top
  assert.ok(r0 > 240 && g0 > 230 && b0 > 210, `cream frame, got ${[r0, g0, b0]}`);
  answer = doodle("Mia");
  const other = await call(card, { code: "AB12CD34", image: "doodle" });
  answer = doodle("Utku");
  const plain = await call(card, { code: "AB12CD34", image: "doodle" });
  assert.deepEqual(r.body, plain.body, "a name in the URL is ignored");
  assert.notDeepEqual(r.body, other.body);
  answer = null;
  const someone = await call(card, { code: "AB12CD34", image: "doodle" });
  answer = doodle("日本");
  const unknownGlyphs = await call(card, { code: "AB12CD34", image: "doodle" });
  assert.deepEqual(someone.body, unknownGlyphs.body);
});
