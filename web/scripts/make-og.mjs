// Generates public/og.png (1200x630): a pixel-art share card drawn with plain zlib, no image deps.
import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";

const W = 1200, H = 630, px = Buffer.alloc(W * H * 3);
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const rect = (x, y, w, h, c) => { const [r, g, b] = hex(c); for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) { if (i < 0 || j < 0 || i >= W || j >= H) continue; const o = (j * W + i) * 3; px[o] = r; px[o + 1] = g; px[o + 2] = b; } };

rect(0, 0, W, H, "#f3e2b3");
for (let y = 0; y < H; y += 30) for (let x = (y / 30) % 2 ? 0 : 30; x < W; x += 60) rect(x, y, 30, 30, "#ecd6a0");
rect(0, 0, W, 24, "#5a3a1e"); rect(0, H - 24, W, 24, "#5a3a1e"); rect(0, 0, 24, H, "#5a3a1e"); rect(W - 24, 0, 24, H, "#5a3a1e");
// hamster, 16x16 grid at scale 18
const S = 18, ox = 120, oy = 170;
const ham = [
  "....oo....oo....", "...oOOo..oOOo...", "...oOOoooOOOo...", "..oBBBBBBBBBBo..", ".oBBBBBBBBBBBBo.", ".oBBkkBBBBkkBBo.",
  ".oBBkkBBBBkkBBo.", ".oBBBBBBBBBBBBo.", ".oBCCCCppCCCCBo.", ".oBCCCCCCCCCCBo.", "..oCCCCCCCCCCo..", "..oBCCCCCCCCBo..",
  "...oBBBBBBBBo...", "....oooooooo....",
];
const pal = { o: "#2e1c0e", O: "#e8a46a", B: "#d98e4a", k: "#2e1c0e", C: "#f6e7c4", p: "#c0546b" };
ham.forEach((row, j) => [...row].forEach((ch, i) => pal[ch] && rect(ox + i * S, oy + j * S, S, S, pal[ch])));
// 5x7 glyphs
const G = {
  S: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], Q: ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
  U: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], E: ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
  K: ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], W: ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
  A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
  T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], N: ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
  " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
};
const text = (s, x, y, k, c) => [...s].forEach((ch, n) => G[ch].forEach((row, j) => [...row].forEach((b, i) => b === "1" && rect(x + n * 6 * k + i * k, y + j * k, k, k, c))));
text("SQUEEK", 470, 150, 16, "#5a3a1e");
text("WARS", 470, 290, 16, "#8a5a2b");
text("TESTNET", 474, 440, 8, "#3f6b2a");

const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; px.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3); }
const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
writeFileSync(new URL("../public/og.png", import.meta.url), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]));
console.log("wrote public/og.png");
