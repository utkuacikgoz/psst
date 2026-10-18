// Draws a 1200x630 link-preview card as a PNG with no dependencies: the
// letters are Inter Tight Black pre-rendered by make_glyphs.py (glyphs.bin),
// laid out with the font's kerning, scaled with area averaging, and the PNG is
// written with Node's zlib.

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const WIDTH = 1200;
const HEIGHT = 630;
const PINK = [0xC2, 0x18, 0x5B]; // Psst pink #C2185B
const WHITE = [255, 255, 255];
const BLACK = [0, 0, 0];

let font = null;
function loadFont() {
  if (font) return font;
  const file = fs.readFileSync(path.join(__dirname, "glyphs.bin"));
  if (file.toString("latin1", 0, 4) !== "PSG1") throw new Error("glyphs.bin: bad header");
  const length = file.readUInt32BE(4);
  const header = JSON.parse(file.toString("utf8", 8, 8 + length));
  font = { ...header, bits: zlib.inflateSync(file.subarray(8 + length)) };
  return font;
}

function canDraw(text) {
  const { glyphs } = loadFont();
  return Array.from(text).every((ch) => glyphs[ch.codePointAt(0)]);
}

// Width in pixels of `text` at `size`, with tracking in em.
function measure(text, size, tracking = 0) {
  const { glyphs, kern, size: base } = loadFont();
  let x = 0;
  let prev = null;
  for (const ch of Array.from(text)) {
    const g = glyphs[ch.codePointAt(0)];
    if (!g) continue;
    if (prev) x += (kern[prev + ch] || 0) + tracking * base;
    x += g[0];
    prev = ch;
  }
  return (x * size) / base;
}

// The text as an alpha mask at the glyphs' own size.
function mask(text, tracking) {
  const { glyphs, kern, size: base, ascent, descent, bits } = loadFont();
  const width = Math.ceil(measure(text, base, tracking)) + base;
  const height = ascent + descent;
  const out = new Uint8Array(width * height);
  let x = Math.round(base * 0.1);
  let prev = null;
  for (const ch of Array.from(text)) {
    const g = glyphs[ch.codePointAt(0)];
    if (!g) continue;
    if (prev) x += (kern[prev + ch] || 0) + tracking * base;
    const [advance, x0, y0, w, h, offset] = g;
    const left = Math.round(x + x0);
    const top = ascent + y0;
    const stride = Math.ceil(w / 2);
    for (let row = 0; row < h; row++) {
      const y = top + row;
      if (y < 0 || y >= height) continue;
      for (let col = 0; col < w; col++) {
        const px = left + col;
        if (px < 0 || px >= width) continue;
        const byte = bits[offset + row * stride + (col >> 1)];
        const a = ((col & 1) ? byte & 15 : byte >> 4) * 17;
        const i = y * width + px;
        if (a > out[i]) out[i] = a;
      }
    }
    x += advance;
    prev = ch;
  }
  return { width, height, data: out, originX: Math.round(base * 0.1), ascent };
}

// Box weights for shrinking `from` samples to `to` samples.
function weights(from, scale) {
  const to = Math.ceil(from * scale);
  const list = [];
  for (let j = 0; j < to; j++) {
    const start = j / scale;
    const end = Math.min(from, (j + 1) / scale);
    const taps = [];
    for (let i = Math.floor(start); i < end; i++) {
      const w = Math.min(end, i + 1) - Math.max(start, i);
      if (w > 0) taps.push(i, w * scale);
    }
    list.push(taps);
  }
  return list;
}

function blank(color) {
  const pixels = new Uint8Array(WIDTH * HEIGHT * 3);
  for (let i = 0; i < pixels.length; i += 3) pixels.set(color, i);
  return pixels;
}

function blend(pixels, x, y, color, alpha) {
  if (x < 0 || y < 0 || x >= WIDTH || y >= HEIGHT || alpha <= 0) return;
  const i = (y * WIDTH + x) * 3;
  const a = Math.min(1, alpha);
  for (let c = 0; c < 3; c++) pixels[i + c] = Math.round(pixels[i + c] * (1 - a) + color[c] * a);
}

// The text as coverage (0..1) at `size`, area-averaged from the glyph size.
function scaledMask(text, size, tracking) {
  const m = mask(text, tracking);
  const scale = Math.min(1, size / loadFont().size);
  const cols = weights(m.width, scale);
  const rows = weights(m.height, scale);
  const across = new Float32Array(cols.length * m.height);
  for (let r = 0; r < m.height; r++) {
    for (let j = 0; j < cols.length; j++) {
      const taps = cols[j];
      let sum = 0;
      for (let t = 0; t < taps.length; t += 2) sum += m.data[r * m.width + taps[t]] * taps[t + 1];
      across[r * cols.length + j] = sum;
    }
  }
  const data = new Float32Array(cols.length * rows.length);
  for (let k = 0; k < rows.length; k++) {
    const taps = rows[k];
    for (let j = 0; j < cols.length; j++) {
      let sum = 0;
      for (let t = 0; t < taps.length; t += 2) sum += across[taps[t] * cols.length + j] * taps[t + 1];
      data[k * cols.length + j] = sum / 255;
    }
  }
  return { width: cols.length, height: rows.length, data, originX: m.originX * scale, ascent: m.ascent * scale };
}

// Draws `text` with its left edge at x and its baseline at y.
function drawText(pixels, text, x, y, size, color, { tracking = 0, opacity = 1 } = {}) {
  const m = scaledMask(text, size, tracking);
  const left = Math.round(x - m.originX);
  const top = Math.round(y - m.ascent);
  for (let k = 0; k < m.height; k++) {
    for (let j = 0; j < m.width; j++) {
      const a = m.data[k * m.width + j];
      if (a > 0) blend(pixels, left + j, top + k, color, a * opacity);
    }
  }
}

// Draws `text` centred on (cx, cy) (the middle of its capitals), turned by
// `degrees` clockwise, sampling the scaled mask bilinearly.
function drawTextRotated(pixels, text, cx, cy, size, degrees, color, { tracking = 0, opacity = 1 } = {}) {
  const m = scaledMask(text, size, tracking);
  const width = measure(text, size, tracking);
  const midX = m.originX + width / 2;
  const midY = m.ascent - size * 0.36;
  const angle = (degrees * Math.PI) / 180;
  const cos = Math.cos(angle), sin = Math.sin(angle);
  const reach = Math.ceil(Math.hypot(m.width, m.height));
  const sample = (x, y) => (x < 0 || y < 0 || x >= m.width || y >= m.height ? 0 : m.data[y * m.width + x]);
  for (let py = Math.floor(cy - reach); py <= cy + reach; py++) {
    for (let px = Math.floor(cx - reach); px <= cx + reach; px++) {
      const dx = px + 0.5 - cx, dy = py + 0.5 - cy;
      const lx = dx * cos + dy * sin + midX - 0.5;
      const ly = -dx * sin + dy * cos + midY - 0.5;
      const x0 = Math.floor(lx), y0 = Math.floor(ly);
      if (x0 < -1 || y0 < -1 || x0 >= m.width || y0 >= m.height) continue;
      const fx = lx - x0, fy = ly - y0;
      const a = sample(x0, y0) * (1 - fx) * (1 - fy) + sample(x0 + 1, y0) * fx * (1 - fy)
        + sample(x0, y0 + 1) * (1 - fx) * fy + sample(x0 + 1, y0 + 1) * fx * fy;
      if (a > 0) blend(pixels, px, py, color, a * opacity);
    }
  }
}

// Fills a w x h rounded rectangle centred on (cx, cy), turned by `degrees`
// clockwise, antialiased from its signed distance. `color` may be a function
// of the local position (u, v in 0..1) for gradients; `blur` softens the edge
// (for shadows).
function rotatedRect(pixels, cx, cy, w, h, radius, degrees, color, { opacity = 1, blur = 0 } = {}) {
  const angle = (degrees * Math.PI) / 180;
  const cos = Math.cos(angle), sin = Math.sin(angle);
  const reach = Math.ceil(Math.hypot(w, h) / 2 + blur + 2);
  for (let py = Math.floor(cy - reach); py <= cy + reach; py++) {
    for (let px = Math.floor(cx - reach); px <= cx + reach; px++) {
      const dx = px + 0.5 - cx, dy = py + 0.5 - cy;
      const lx = dx * cos + dy * sin, ly = -dx * sin + dy * cos;
      const qx = Math.abs(lx) - w / 2 + radius, qy = Math.abs(ly) - h / 2 + radius;
      const d = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - radius;
      const cover = blur > 0 ? Math.max(0, Math.min(1, 0.5 - d / (2 * blur))) : Math.max(0, Math.min(1, 0.5 - d));
      if (cover <= 0) continue;
      const c = typeof color === "function" ? color(lx / w + 0.5, ly / h + 0.5) : color;
      blend(pixels, px, py, c, cover * opacity);
    }
  }
}

// A small pencil (the ✎ of the SEALED sticker; the font has no such glyph),
// centred on (cx, cy), pointing down-left, turned with its sticker.
function pencil(pixels, cx, cy, length, degrees, color) {
  const body = length * 0.72, thick = length * 0.22, tip = length * 0.28;
  const turn = degrees - 45;
  const rad = (turn * Math.PI) / 180;
  const ax = Math.cos(rad), ay = Math.sin(rad);
  // body centred a little up-right of the middle, the tip below-left of it
  const bx = cx + ax * tip / 2, by = cy + ay * tip / 2;
  rotatedRect(pixels, bx, by, body, thick, thick * 0.2, turn, color);
  const tx = bx - ax * (body / 2), ty = by - ay * (body / 2);
  const end = [tx - ax * tip, ty - ay * tip];
  const side = [-ay * thick / 2, ax * thick / 2];
  const tri = [[tx + side[0], ty + side[1]], [tx - side[0], ty - side[1]], end];
  const xs = tri.map((p) => p[0]), ys = tri.map((p) => p[1]);
  const edge = (a, b, x, y) => (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]);
  for (let py = Math.floor(Math.min(...ys)); py <= Math.max(...ys); py++) {
    for (let px = Math.floor(Math.min(...xs)); px <= Math.max(...xs); px++) {
      let hits = 0;
      for (let s = 0; s < 16; s++) {
        const x = px + ((s % 4) + 0.5) / 4, y = py + (Math.floor(s / 4) + 0.5) / 4;
        const e0 = edge(tri[0], tri[1], x, y), e1 = edge(tri[1], tri[2], x, y), e2 = edge(tri[2], tri[0], x, y);
        if ((e0 >= 0 && e1 >= 0 && e2 >= 0) || (e0 <= 0 && e1 <= 0 && e2 <= 0)) hits++;
      }
      if (hits) blend(pixels, px, py, color, hits / 16);
    }
  }
}

function roundedRect(pixels, x, y, w, h, radius, color, opacity) {
  for (let py = Math.floor(y); py < Math.ceil(y + h); py++) {
    for (let px = Math.floor(x); px < Math.ceil(x + w); px++) {
      const cx = Math.max(x + radius - (px + 0.5), 0, (px + 0.5) - (x + w - radius));
      const cy = Math.max(y + radius - (py + 0.5), 0, (py + 0.5) - (y + h - radius));
      const d = Math.hypot(cx, cy) - radius;
      blend(pixels, px, py, color, Math.max(0, Math.min(1, 0.5 - d)) * opacity);
    }
  }
}

const CRC = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});
function crc32(buffer) {
  let c = -1;
  for (let i = 0; i < buffer.length; i++) c = CRC[(c ^ buffer[i]) & 255] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "latin1");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

function png(pixels) {
  const raw = Buffer.alloc((WIDTH * 3 + 1) * HEIGHT);
  for (let y = 0; y < HEIGHT; y++) {
    raw[y * (WIDTH * 3 + 1)] = 0;
    Buffer.from(pixels.buffer, y * WIDTH * 3, WIDTH * 3).copy(raw, y * (WIDTH * 3 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(WIDTH, 0);
  ihdr.writeUInt32BE(HEIGHT, 4);
  ihdr.set([8, 2, 0, 0, 0], 8); // 8-bit RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 6 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const PAD = 80;
const TIGHT = -0.045; // the pages' h1 letter-spacing
const MAX_SIZE = 128;
const MIN_SIZE = 64;

function fitSize(text, max) {
  const width = measure(text, 100, TIGHT);
  return Math.min(max, Math.floor((100 * (WIDTH - 2 * PAD)) / width));
}

// "<Name> pssted you" on one line when it fits big, else the name over the
// verb; a very long name is shortened with "…".
function headline(name, verb) {
  const one = `${name} ${verb}`;
  if (fitSize(one, MAX_SIZE) >= 100) return { lines: [one], size: fitSize(one, MAX_SIZE) };
  let first = name;
  while (fitSize(first, MAX_SIZE) < MIN_SIZE && Array.from(first).length > 1) {
    first = Array.from(first.replace(/…$/, "")).slice(0, -1).join("").trimEnd() + "…";
  }
  return { lines: [first, verb], size: Math.max(MIN_SIZE, Math.min(fitSize(first, MAX_SIZE), fitSize(verb, MAX_SIZE))) };
}

const CREAM = [0xFB, 0xF6, 0xEA];
const INK = [0x24, 0x1B, 0x2C];
const STICKER_INK = [0xAC, 0x3E, 0x68];
const FROST_FROM = [0xEF, 0xA9, 0xC4];
const FROST_TO = [0xD4, 0x6A, 0x92];

// Frosted pink, the same as the page's .polaroid .frost: a diagonal pink with a
// soft white glow up-left. Never strokes: the doodle stays sealed.
function frost(u, v) {
  const t = Math.max(0, Math.min(1, (u + v) / 2));
  const base = FROST_FROM.map((c, i) => c + (FROST_TO[i] - c) * t);
  const glow = 0.55 * Math.max(0, 1 - Math.hypot(u - 0.3, v - 0.25) / 0.6);
  return base.map((c) => c + (255 - c) * glow);
}

// Greedy word wrap of `words` into `width` at the largest size that fits
// `height`; a name too long even at the smallest size is shortened with "…".
function wrapped(name, rest, width, height, max = 112, min = 48) {
  let first = name;
  for (;;) {
    for (let size = max; size >= min; size -= 2) {
      const lines = [];
      for (const word of [...first.split(" "), ...rest.split(" ")]) {
        if (measure(word, size, TIGHT) > width) { lines.length = 99; break; }
        const last = lines[lines.length - 1];
        if (last && measure(last + " " + word, size, TIGHT) <= width) lines[lines.length - 1] = last + " " + word;
        else lines.push(word);
      }
      if (lines.length * size * 0.98 <= height) return { lines, size };
    }
    if (Array.from(first).length <= 1) return { lines: [first, ...rest.split(" ")], size: min };
    first = Array.from(first.replace(/…$/, "")).slice(0, -1).join("").trimEnd() + "…";
  }
}

// The sealed doodle polaroid, centred on (cx, cy), `k` times the page's 150px
// one, turned `degrees` clockwise. The SEALED sticker is turned -6deg on its own.
function polaroid(pixels, cx, cy, k, degrees, who) {
  const pad = 10 * k, bottom = 26 * k, inner = 130 * k;
  const w = inner + 2 * pad, h = inner + pad + bottom;
  const rad = (degrees * Math.PI) / 180;
  const at = (lx, ly) => [cx + lx * Math.cos(rad) - ly * Math.sin(rad), cy + lx * Math.sin(rad) + ly * Math.cos(rad)];
  rotatedRect(pixels, cx, cy + 6 * k, w, h, 14 * k, degrees, BLACK, { opacity: 0.28, blur: 9 * k });
  rotatedRect(pixels, cx, cy, w, h, 14 * k, degrees, CREAM);
  const [ix, iy] = at(0, -h / 2 + pad + inner / 2);
  rotatedRect(pixels, ix, iy, inner, inner, 6 * k, degrees, frost);

  // "from <Name>" under the picture, shrunk or shortened to fit.
  let label = `from ${who}`;
  let size = 12 * k;
  while (measure(label, size, -0.01) > inner && size > 8 * k) size -= 1;
  while (measure(label, size, -0.01) > inner && Array.from(label).length > 6) {
    label = Array.from(label.replace(/…$/, "")).slice(0, -1).join("").trimEnd() + "…";
  }
  const [fx, fy] = at(0, h / 2 - bottom / 2);
  drawTextRotated(pixels, label, fx, fy, size, degrees, INK, { tracking: -0.01 });

  // The white SEALED ✎ sticker over the middle of the picture.
  const tilt = -6;
  const text = "SEALED";
  const textSize = 12 * k;
  const textWidth = measure(text, textSize, 0.08);
  const pen = 13 * k, gap = 5 * k;
  const sw = textWidth + gap + pen + 20 * k, sh = 26 * k;
  rotatedRect(pixels, ix, iy + 2 * k, sw, sh, 5 * k, tilt, BLACK, { opacity: 0.18, blur: 3 * k });
  rotatedRect(pixels, ix, iy, sw, sh, 5 * k, tilt, WHITE);
  const tr = (tilt * Math.PI) / 180;
  const along = (d) => [ix + d * Math.cos(tr), iy + d * Math.sin(tr)];
  const content = textWidth + gap + pen;
  const [tx, ty] = along(-content / 2 + textWidth / 2);
  drawTextRotated(pixels, text, tx, ty, textSize, tilt, STICKER_INK, { tracking: 0.08 });
  const [px, py] = along(content / 2 - pen / 2);
  pencil(pixels, px, py, pen, tilt, STICKER_INK);
}

// kind "p": "<Name> pssted you" + "1 Psst waiting"; kind "invite": "<Name> invited you";
// kind "doodle": "<Name> drew you something" + the sealed polaroid (owner picks 2A 3A).
function renderCard(name, kind) {
  const who = name && canDraw(name) ? name : "Someone";
  const pixels = blank(PINK);
  drawText(pixels, "psst", PAD, PAD + 44, 60, WHITE, { tracking: -0.044 });

  if (kind === "doodle") {
    const { lines, size } = wrapped(who, "drew you something", WIDTH * 0.45, HEIGHT - 2 * PAD - 110);
    const lineHeight = Math.round(size * 0.98);
    let top = Math.max(PAD + 90, Math.round((HEIGHT - lines.length * lineHeight) / 2 + 40));
    for (const line of lines) {
      drawText(pixels, line, PAD, top + Math.round(size * 0.8), size, WHITE, { tracking: TIGHT });
      top += lineHeight;
    }
    polaroid(pixels, 905, 330, 2.3, 6, who);
    return png(pixels);
  }

  const { lines, size } = headline(who, kind === "p" ? "pssted you" : "invited you");
  const lineHeight = Math.round(size * 0.98);
  const pill = kind === "p" ? { size: 44, height: 88 } : null;
  const block = lines.length * lineHeight + (pill ? 36 + pill.height : 0);
  let top = Math.max(PAD + 90, Math.round((HEIGHT - block) / 2 + 40));
  for (const line of lines) {
    drawText(pixels, line, PAD, top + Math.round(size * 0.8), size, WHITE, { tracking: TIGHT });
    top += lineHeight;
  }
  if (pill) {
    const text = "1 Psst waiting";
    const width = Math.ceil(measure(text, pill.size, -0.01)) + 64;
    top += 36;
    roundedRect(pixels, PAD, top, width, pill.height, 26, BLACK, 0.16);
    drawText(pixels, text, PAD + 32, top + Math.round(pill.height / 2 + pill.size * 0.36), pill.size, WHITE, { tracking: -0.01 });
  }
  return png(pixels);
}

module.exports = { renderCard, canDraw, measure, WIDTH, HEIGHT };
