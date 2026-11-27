"""Builds a design-preview page in the owner's format (docs/DESIGN_PREVIEWS.md):
one page, numbered topics, A/B/C pick buttons that save to the artifact's db
(doc picks/<round>), a Copy picks fallback and an Anything else box.

    from preview_page import page
    html = page(title="Psst Rate Row", eyebrow="Psst 1.0.10 · for your approval",
                h1="rate psst", lede="…", round_id="rate-row",
                topics=[{"title": "…", "note": "…", "html": "<div>…</div>",
                         "options": [("A", "Front page"), ("B", "Inside"), ("C", "No row")]}],
                extra_css="…")

The first option of each topic is marked Recommended. Publish the result with the
Artifact tool and capabilities {"db": {}}.
"""
import html as _html

CSS = """
:root{--bg:#F4F0F7;--fg:#241B2C;--muted:#66586E;--rule:#DDD3E5;--accent:#713F93;--chip:#FFFFFF;--on-accent:#FFFFFF;--ok:#187F69;--display:"Inter Tight",system-ui,-apple-system,sans-serif;--body:"Inter Tight",system-ui,-apple-system,sans-serif}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#16111B;--fg:#F1ECF5;--muted:#B4A7BF;--rule:#322839;--accent:#C59BE3;--chip:#221A29;--on-accent:#16111B;--ok:#5FD1B2;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#16111B;--fg:#F1ECF5;--muted:#B4A7BF;--rule:#322839;--accent:#C59BE3;--chip:#221A29;--on-accent:#16111B;--ok:#5FD1B2;color-scheme:dark}
body{background:var(--bg);color:var(--fg);font:16px/1.5 var(--body);margin:0}
.wrap{max-width:1180px;margin:0 auto;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:24px 96px;display:grid;gap:40px}
header{display:grid;gap:10px;max-width:68ch}
.eyebrow{font-weight:700;font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}
h1{font:900 clamp(32px,6vw,52px)/1 var(--display);letter-spacing:-.02em;margin:0;text-transform:lowercase;color:var(--accent)}
h2{font:900 24px/1.1 var(--display);text-transform:uppercase;margin:0;display:flex;gap:12px;align-items:baseline;text-wrap:balance}
h2 .num{font-size:34px;color:var(--accent);min-width:1.2em}
p{margin:0}.lede,.note{color:var(--muted);max-width:72ch}
section{display:grid;gap:14px;border-top:1px solid var(--rule);padding-top:22px}
.opts{display:flex;flex-wrap:wrap;gap:8px}
.opts button{font:600 15px var(--body);color:var(--fg);background:var(--chip);border:1.5px solid var(--rule);padding:10px 14px;min-height:44px;cursor:pointer;text-align:left}
.opts button b{font-weight:900;margin-right:6px}
.opts button .rec{font-size:11px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--ok);margin-left:6px}
.opts button[aria-pressed="true"]{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.opts button[aria-pressed="true"] .rec{color:var(--on-accent)}
.opts button:focus-visible,textarea:focus-visible,.bar button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
textarea{font:15px/1.4 var(--body);color:var(--fg);background:var(--chip);border:1.5px solid var(--rule);padding:10px;width:100%;box-sizing:border-box;min-height:44px}
.policy{background:var(--chip);border:1px solid var(--rule);padding:14px 18px;max-width:80ch}.policy li{margin:6px 0}
.bar{position:sticky;bottom:0;background:var(--chip);border-top:1px solid var(--rule);padding-block:10px calc(10px + env(safe-area-inset-bottom,0px));padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center;justify-content:space-between}
.bar .sum{font-weight:800}.bar .state{font-size:13px;color:var(--muted)}.bar .state.ok{color:var(--ok)}
.bar button{font:700 14px var(--body);background:transparent;color:var(--accent);border:1.5px solid var(--accent);padding:8px 12px;min-height:40px;cursor:pointer}
"""

SCRIPT = """
<div class="bar" role="status">
  <span class="sum" id="sum">No picks yet</span>
  <span class="state" id="state">Picks save here when you tap</span>
  <button type="button" id="copy">Copy picks</button>
</div>
<script>
(function () {
  var picks = {}, notes = "", docRef = null, saveTimer = null;
  var stateEl = document.getElementById("state"), sumEl = document.getElementById("sum"), notesEl = document.getElementById("notes");
  var order = __ORDER__;
  function summary() {
    var parts = [];
    order.forEach(function (k) { if (picks[k]) parts.push(k + picks[k]); });
    return parts.length ? parts.join(" · ") : "No picks yet";
  }
  function render() {
    document.querySelectorAll(".picker").forEach(function (p) {
      var key = p.getAttribute("data-key");
      p.querySelectorAll("button").forEach(function (b) {
        b.setAttribute("aria-pressed", picks[key] === b.getAttribute("data-v") ? "true" : "false");
      });
    });
    sumEl.textContent = summary();
  }
  function setState(text, ok) { stateEl.textContent = text; stateEl.className = "state" + (ok ? " ok" : ""); }
  function queueSave() {
    if (!docRef) { setState("Not saved on this view. Copy your picks and paste them to Claude"); return; }
    clearTimeout(saveTimer);
    setState("Saving…");
    saveTimer = setTimeout(function () {
      var body = { notes: notes, summary: summary(), updatedAt: new Date().toISOString() };
      order.forEach(function (k) { if (picks[k]) body["pick_" + k] = picks[k]; });
      docRef.set(body).then(function () { setState("Saved ✓ Claude can read these", true); })
        .catch(function (e) {
          setState(e && e.code === "invalid_argument" ? "You can't save picks on this page. Copy them instead"
                                                      : "Couldn't save. Tap a pick again to retry");
        });
    }, 400);
  }
  document.querySelectorAll(".picker").forEach(function (p) {
    var key = p.getAttribute("data-key");
    p.addEventListener("click", function (ev) {
      var b = ev.target.closest("button");
      if (!b) return;
      picks[key] = b.getAttribute("data-v");
      render();
      queueSave();
    });
  });
  notesEl.addEventListener("change", function () { notes = notesEl.value; queueSave(); });
  document.getElementById("copy").addEventListener("click", function () {
    var text = summary() + (notes ? " — " + notes : "");
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { setState("Copied", true); }, function () { sumEl.textContent = text; });
    } else { sumEl.textContent = text; }
  });
  render();
  function connect(tries) {
    if (!(window.claude && window.claude.use)) {
      if (tries > 0) { setTimeout(function () { connect(tries - 1); }, 250); }
      else { setState("Not saved on this view. Copy your picks and paste them to Claude"); }
      return;
    }
    window.claude.use("db").then(function (db) {
      if (!db) { setState("Not saved on this view. Copy your picks and paste them to Claude"); return; }
      docRef = db.doc("picks/__ROUND__");
      docRef.get().then(function (snap) {
        if (snap.exists) {
          var d = snap.data() || {};
          order.forEach(function (k) { if (d["pick_" + k]) picks[k] = d["pick_" + k]; });
          if (typeof d.notes === "string") { notes = d.notes; notesEl.value = notes; }
          render();
          setState("Your saved picks", true);
        }
      }).catch(function () {});
    });
  }
  connect(20);
})();
</script>
"""


def page(title, eyebrow, h1, lede, round_id, topics, extra_css="", notes_placeholder="e.g. 1A but shorter"):
    def opts(options):
        return "".join(f'<button type="button" data-v="{v}"><b>{v}</b>{_html.escape(label)}'
                       f'{"<span class=rec>Recommended</span>" if i == 0 else ""}</button>'
                       for i, (v, label) in enumerate(options))
    out = [f"<title>{_html.escape(title)}</title>",
           '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter+Tight:wght@500;600;700;900&display=swap">',
           f"<style>{CSS}{extra_css}</style>",
           f'<div class="wrap">\n<header><div class="eyebrow">{eyebrow}</div><h1>{h1}</h1><p class="lede">{lede}</p></header>']
    for i, t in enumerate(topics, 1):
        note = f'<p class="note">{t["note"]}</p>' if t.get("note") else ""
        out.append(f'<section id="t{i}"><h2><span class="num">{i}</span>{t["title"]}</h2>{note}'
                   f'<div class="picker" data-key="{i}"><div class="opts">{opts(t["options"])}</div></div>{t.get("html", "")}</section>')
    out.append('<section><h2><span class="num">+</span>Anything else</h2><label class="note" for="notes">Changes you want, in your own words.</label>'
               f'<textarea id="notes" rows="3" placeholder="{_html.escape(notes_placeholder)}"></textarea></section>\n</div>')
    order = "[" + ",".join(f'"{i}"' for i in range(1, len(topics) + 1)) + "]"
    out.append(SCRIPT.replace("__ORDER__", order).replace("__ROUND__", round_id))
    return "\n".join(out)
