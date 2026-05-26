import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';

const root = process.argv[2];
const sizes = [
  ['Icon-20@2x.png', 40],
  ['Icon-20@3x.png', 60],
  ['Icon-29@2x.png', 58],
  ['Icon-29@3x.png', 87],
  ['Icon-40@2x.png', 80],
  ['Icon-40@3x.png', 120],
  ['Icon-60@2x.png', 120],
  ['Icon-60@3x.png', 180],
  ['Icon-20-ipad@1x.png', 20],
  ['Icon-20-ipad@2x.png', 40],
  ['Icon-29-ipad@1x.png', 29],
  ['Icon-29-ipad@2x.png', 58],
  ['Icon-40-ipad@1x.png', 40],
  ['Icon-40-ipad@2x.png', 80],
  ['Icon-76@1x.png', 76],
  ['Icon-76@2x.png', 152],
  ['Icon-83.5@2x.png', 167],
  ['Icon-1024.png', 1024],
];

const crcTable = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const name = Buffer.from(type);
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  name.copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(Buffer.concat([name, data])), 8 + data.length);
  return out;
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function blend(base, over, alpha) {
  return [
    Math.round(lerp(base[0], over[0], alpha)),
    Math.round(lerp(base[1], over[1], alpha)),
    Math.round(lerp(base[2], over[2], alpha)),
  ];
}

function insideRoundRect(x, y, size, inset, radius) {
  const min = inset;
  const max = size - inset;
  const cx = x < min + radius ? min + radius : x > max - radius ? max - radius : x;
  const cy = y < min + radius ? min + radius : y > max - radius ? max - radius : y;
  const dx = x - cx;
  const dy = y - cy;
  return x >= min && x <= max && y >= min && y <= max && dx * dx + dy * dy <= radius * radius;
}

function fillRect(img, size, x0, y0, w, h, color) {
  for (let y = Math.max(0, y0); y < Math.min(size, y0 + h); y++) {
    for (let x = Math.max(0, x0); x < Math.min(size, x0 + w); x++) {
      const idx = (y * size + x) * 4;
      img[idx] = color[0];
      img[idx + 1] = color[1];
      img[idx + 2] = color[2];
      img[idx + 3] = 255;
    }
  }
}

function drawGlyphs(img, size) {
  const scale = size / 1024;
  const c = [246, 250, 255];
  const blue = [118, 210, 255];
  const unit = Math.max(1, Math.round(34 * scale));
  const top = Math.round(384 * scale);
  const left = Math.round(250 * scale);
  const h = Math.round(250 * scale);
  const gap = Math.round(36 * scale);
  const w = Math.round(112 * scale);

  // P
  fillRect(img, size, left, top, unit, h, c);
  fillRect(img, size, left, top, w, unit, c);
  fillRect(img, size, left, top + Math.round(92 * scale), w, unit, c);
  fillRect(img, size, left + w - unit, top, unit, Math.round(126 * scale), c);

  // S
  const sx = left + w + gap;
  fillRect(img, size, sx, top, w, unit, c);
  fillRect(img, size, sx, top + Math.round(92 * scale), w, unit, c);
  fillRect(img, size, sx, top + h - unit, w, unit, c);
  fillRect(img, size, sx, top, unit, Math.round(126 * scale), c);
  fillRect(img, size, sx + w - unit, top + Math.round(92 * scale), unit, Math.round(158 * scale), c);

  // 4
  const fx = sx + w + gap;
  fillRect(img, size, fx, top, unit, Math.round(126 * scale), c);
  fillRect(img, size, fx + w - unit, top, unit, h, c);
  fillRect(img, size, fx, top + Math.round(110 * scale), w, unit, c);

  const iosTop = Math.round(695 * scale);
  fillRect(img, size, Math.round(410 * scale), iosTop, Math.round(204 * scale), Math.max(2, Math.round(18 * scale)), blue);
}

function makePng(size) {
  const pixels = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const t = (x + y) / (2 * size);
      let rgb = [9, 11, 16];
      if (insideRoundRect(x, y, size, size * 0.08, size * 0.18)) {
        const a = [16, 118, 205];
        const b = t < 0.56 ? [102, 72, 218] : [32, 179, 140];
        rgb = [Math.round(lerp(a[0], b[0], t)), Math.round(lerp(a[1], b[1], t)), Math.round(lerp(a[2], b[2], t))];
      }
      if (insideRoundRect(x, y, size, size * 0.18, size * 0.12)) {
        rgb = blend(rgb, [13, 16, 23], 0.9);
      }
      const idx = (y * size + x) * 4;
      pixels[idx] = rgb[0];
      pixels[idx + 1] = rgb[1];
      pixels[idx + 2] = rgb[2];
      pixels[idx + 3] = 255;
    }
  }
  drawGlyphs(pixels, size);

  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    pixels.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

for (const [name, size] of sizes) {
  writeFileSync(join(root, name), makePng(size));
}
