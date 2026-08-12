// Generates assets/clawd.ico (and a preview PNG) with no dependencies.
// Clawd is pixel art, so every size is drawn on an integer unit grid: no antialiasing,
// no resampling, crisp at 16px and at 256px. PNG is encoded by hand on top of zlib.
import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "assets");

const CORAL = [0xd9, 0x77, 0x57];
const INK = [0x18, 0x14, 0x12];

// Silhouette on the unit grid, matching Character.BuildParts / Tray.CrabRects.
// Body spans x -5..5, y -4..3; claws stick out to +-6; legs hang to y 5.
function crabRects(u) {
  const r = [
    [-5 * u, -4 * u, 10 * u, 7 * u], // body
    [-6 * u, -2 * u, 1 * u, 2 * u], // left claw
    [5 * u, -2 * u, 1 * u, 2 * u], // right claw
  ];
  for (const x of [-5, -2.25, 0.5, 3.25]) r.push([x * u, 3 * u, 1.75 * u, 2 * u]);
  r.push([-0.5 * u, 3 * u, 1 * u, 1 * u]); // shallow middle notch
  return r;
}

function render(S) {
  const px = Buffer.alloc(S * S * 4);
  const u = Math.max(1, Math.floor(S / 12.6));
  const cx = Math.round((S - 12 * u) / 2) + 6 * u;
  const cy = Math.round((S - 9 * u) / 2) + 4 * u;

  const fill = (x, y, w, h, col) => {
    for (let yy = Math.round(y); yy < Math.round(y + h); yy++) {
      if (yy < 0 || yy >= S) continue;
      for (let xx = Math.round(x); xx < Math.round(x + w); xx++) {
        if (xx < 0 || xx >= S) continue;
        const i = (yy * S + xx) * 4;
        px[i] = col[0];
        px[i + 1] = col[1];
        px[i + 2] = col[2];
        px[i + 3] = 255;
      }
    }
  };

  for (const [x, y, w, h] of crabRects(u)) fill(cx + x, cy + y, w, h, CORAL);

  const e = Math.max(1, Math.round(1.7 * u));
  for (const s of [-1, 1]) {
    fill(cx + Math.round(s * 2.6 * u - e / 2), cy + Math.round(-2.05 * u - e / 2), e, e, INK);
  }
  return px;
}

// ---- PNG ----
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function png(S, px) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(S, 0);
  ihdr.writeUInt32BE(S, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc(S * (S * 4 + 1));
  for (let y = 0; y < S; y++) {
    raw[y * (S * 4 + 1)] = 0; // filter: none
    px.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ---- ICO ----
function ico(entries) {
  const dir = Buffer.alloc(6 + entries.length * 16);
  dir.writeUInt16LE(0, 0);
  dir.writeUInt16LE(1, 2);
  dir.writeUInt16LE(entries.length, 4);
  let offset = dir.length;
  entries.forEach((e, i) => {
    const p = 6 + i * 16;
    dir[p] = e.size >= 256 ? 0 : e.size;
    dir[p + 1] = e.size >= 256 ? 0 : e.size;
    dir.writeUInt16LE(1, p + 4);
    dir.writeUInt16LE(32, p + 6);
    dir.writeUInt32LE(e.data.length, p + 8);
    dir.writeUInt32LE(offset, p + 12);
    offset += e.data.length;
  });
  return Buffer.concat([dir, ...entries.map((e) => e.data)]);
}

mkdirSync(OUT, { recursive: true });
const sizes = [16, 20, 24, 32, 48, 64, 128, 256];
const entries = sizes.map((size) => ({ size, data: png(size, render(size)) }));
writeFileSync(join(OUT, "clawd.ico"), ico(entries));
writeFileSync(join(OUT, "clawd-256.png"), entries[entries.length - 1].data);
console.log("wrote clawd.ico (" + sizes.join(", ") + ") and clawd-256.png");
