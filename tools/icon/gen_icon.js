/* Anatoly uygulama ikonu üretici (saf Node, zlib ile PNG).
 * - icon.png      : koyu zemin + mint halter (legacy/iOS, kenardan kenara)
 * - icon_fg.png   : ŞEFFAF zemin + ortalanmış küçük halter (Android adaptive foreground;
 *                   adaptive maske dış ~%25'i kırptığından glyph güvenli bölgede tutulur)
 * Çalıştır: node tools/icon/gen_icon.js
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const S = 1024;
const bg = [0x0d, 0x0e, 0x12, 0xff];
const mint = [0x00, 0xe5, 0xa0, 0xff];

function newBuf(fill) {
  const buf = Buffer.alloc(S * S * 4);
  if (fill) {
    for (let i = 0; i < S * S; i++) {
      buf[i * 4] = fill[0]; buf[i * 4 + 1] = fill[1];
      buf[i * 4 + 2] = fill[2]; buf[i * 4 + 3] = fill[3];
    }
  }
  return buf;
}

function setPx(buf, x, y, c) {
  if (x < 0 || y < 0 || x >= S || y >= S) return;
  const i = (y * S + x) * 4;
  buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = c[3];
}

function fillRoundRect(buf, x0, y0, x1, y1, r, c) {
  for (let y = Math.round(y0); y < Math.round(y1); y++) {
    for (let x = Math.round(x0); x < Math.round(x1); x++) {
      let dx = 0, dy = 0;
      if (x < x0 + r) dx = x0 + r - x; else if (x > x1 - r) dx = x - (x1 - r);
      if (y < y0 + r) dy = y0 + r - y; else if (y > y1 - r) dy = y - (y1 - r);
      if (dx * dx + dy * dy <= r * r) setPx(buf, x, y, c);
    }
  }
}

// scale: glyph'in toplam genişliğinin kanvasa oranı (~0.6 legacy, ~0.42 adaptive)
function drawDumbbell(buf, scale) {
  const cy = S / 2;
  const cx = S / 2;
  const half = (S * scale) / 2; // bar yarı genişliği
  // bar
  fillRoundRect(buf, cx - half * 0.86, cy - S * 0.035, cx + half * 0.86, cy + S * 0.035, S * 0.02, mint);
  // iç plakalar
  fillRoundRect(buf, cx - half * 0.66, cy - S * 0.20, cx - half * 0.46, cy + S * 0.20, S * 0.03, mint);
  fillRoundRect(buf, cx + half * 0.46, cy - S * 0.20, cx + half * 0.66, cy + S * 0.20, S * 0.03, mint);
  // dış plakalar
  fillRoundRect(buf, cx - half * 0.99, cy - S * 0.135, cx - half * 0.76, cy + S * 0.135, S * 0.025, mint);
  fillRoundRect(buf, cx + half * 0.76, cy - S * 0.135, cx + half * 0.99, cy + S * 0.135, S * 0.025, mint);
}

function encodePng(buf) {
  function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body) >>> 0, 0);
    return Buffer.concat([len, body, crc]);
  }
  function crc32(b) {
    let c = ~0;
    for (let i = 0; i < b.length; i++) {
      c ^= b[i];
      for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
    }
    return ~c;
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc(S * (S * 4 + 1));
  for (let y = 0; y < S; y++) {
    raw[y * (S * 4 + 1)] = 0;
    buf.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0)),
  ]);
}

const outDir = path.join(__dirname, '..', '..', 'assets', 'icon');
fs.mkdirSync(outDir, { recursive: true });

// legacy / iOS: koyu zemin + büyük halter
const main = newBuf(bg);
drawDumbbell(main, 0.6);
fs.writeFileSync(path.join(outDir, 'icon.png'), encodePng(main));

// adaptive foreground: ŞEFFAF zemin + güvenli-bölge halter (kırpılmasın)
const fg = newBuf([0, 0, 0, 0]);
drawDumbbell(fg, 0.42);
fs.writeFileSync(path.join(outDir, 'icon_fg.png'), encodePng(fg));

console.log('icon.png + icon_fg.png yazıldı');
