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

// Draws `text` with its left edge at x and its baseline at y.
function drawText(pixels, text, x, y, size, color, { tracking = 0, opacity = 1 } = {}) {
  const m = mask(text, tracking);
  const scale = Math.min(1, size / loadFont().size);
  const cols = weights(m.width, scale);
  const rows = weights(m.height, scale);
  const left = Math.round(x - m.originX * scale);
  const top = Math.round(y - m.ascent * scale);
  const across = new Float32Array(cols.length * m.height);
  for (let r = 0; r < m.height; r++) {
    for (let j = 0; j < cols.length; j++) {
      const taps = cols[j];
      let sum = 0;
      for (let t = 0; t < taps.length; t += 2) sum += m.data[r * m.width + taps[t]] * taps[t + 1];
      across[r * cols.length + j] = sum;
    }
  }
  for (let k = 0; k < rows.length; k++) {
    const taps = rows[k];
    for (let j = 0; j < cols.length; j++) {
      let sum = 0;
      for (let t = 0; t < taps.length; t += 2) sum += across[taps[t] * cols.length + j] * taps[t + 1];
      if (sum > 0) blend(pixels, left + j, top + k, color, (sum / 255) * opacity);
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

// kind "p": "<Name> pssted you" + "1 Psst waiting"; kind "invite": "<Name> invited you".
function renderCard(name, kind) {
  const who = name && canDraw(name) ? name : "Someone";
  const pixels = blank(PINK);
  drawText(pixels, "psst", PAD, PAD + 44, 60, WHITE, { tracking: -0.044 });

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
