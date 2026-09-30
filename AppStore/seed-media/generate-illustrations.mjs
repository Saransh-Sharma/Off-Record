// Generates the illustrated "photos" attached to screenshot-mode journal entries.
//
//   node AppStore/seed-media/generate-illustrations.mjs
//
// Each scene shows the moment its entry in OffRecord/ScreenshotDataSeeder.swift describes,
// lit for the entry's time of day. Writes SVGs into ./svg, rasterizes them to
// ./photos/<name>.jpg with Quick Look (WebKit) and sips, then removes the SVGs.
// No npm dependencies.

import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const svgDir = join(here, "svg");
const photoDir = join(here, "photos");
const W = 1600;
const H = 1200;

// Brand palette (AppStore/ScreenshotAssets.md) plus a few supporting tones.
const C = {
  plum: "#342044",
  plumSoft: "#5B3F6E",
  sage: "#7FA08A",
  sageDeep: "#4F7360",
  sageLight: "#B9CFBF",
  lavender: "#BBA7E8",
  lavenderLight: "#DCD1F4",
  peach: "#F6B98F",
  peachDeep: "#E98F6B",
  cream: "#FFF8F0",
  blush: "#F4C6D2",
  blushDeep: "#E79BB0",
  amber: "#E8A33D",
  rust: "#C8553A",
  gold: "#F2C14E",
};

// Deterministic PRNG so every run draws the same pictures.
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const f = (n) => Number(n).toFixed(1);

const grad = (id, stops, { x1 = 0, y1 = 0, x2 = 0, y2 = 1 } = {}) =>
  `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops
    .map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`)
    .join("")}</linearGradient>`;

const radial = (id, stops, { cx = 0.5, cy = 0.5, r = 0.5 } = {}) =>
  `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${stops
    .map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`)
    .join("")}</radialGradient>`;

const sharedDefs = `
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18"/></filter>
  <filter id="softer" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="14"/></filter>`;

const frame = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
<defs>${sharedDefs}${defs}</defs>
${body}
</svg>`;

// --- Shared shapes ----------------------------------------------------------

const dropShadow = (x, y, rx, ry = rx, opacity = 0.25) =>
  `<ellipse cx="${f(x + 10)}" cy="${f(y + 16)}" rx="${f(rx)}" ry="${f(ry)}" fill="#1B0F0C" opacity="${opacity}" filter="url(#shadow)"/>`;

const leaf = (x, y, len, angle, fill) =>
  `<g transform="translate(${f(x)} ${f(y)}) rotate(${f(angle)})">
    <path d="M0 0 C ${f(len * 0.3)} ${f(-len * 0.32)}, ${f(len * 0.75)} ${f(-len * 0.3)}, ${f(len)} 0 C ${f(len * 0.75)} ${f(len * 0.3)}, ${f(len * 0.3)} ${f(len * 0.32)}, 0 0 Z" fill="${fill}"/>
    <path d="M${f(len * 0.05)} 0 L${f(len * 0.9)} 0" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="3"/>
  </g>`;

// Smooth ridge line across the canvas: a closed path filled to the bottom.
function ridge(r, baseY, amp, steps, bottom = H) {
  const pts = [];
  for (let i = 0; i <= steps; i++) pts.push([(W / steps) * i, baseY + (r() - 0.5) * 2 * amp]);
  let d = `M0 ${bottom} L${pts[0][0]} ${f(pts[0][1])}`;
  for (let i = 1; i < pts.length; i++) {
    const [px, py] = pts[i - 1];
    const [x, y] = pts[i];
    d += ` Q${f(px)} ${f(py)} ${f((px + x) / 2)} ${f((py + y) / 2)}`;
  }
  const last = pts[pts.length - 1];
  return `${d} L${f(last[0])} ${f(last[1])} L${W} ${bottom} Z`;
}

// Open journal seen from above, with handwriting lines.
function journal(r, x, y, angle, cover = C.lavender) {
  let s = `<g transform="translate(${x} ${y}) rotate(${angle})">
    <rect x="-330" y="-215" width="660" height="440" rx="18" fill="#000" opacity="0.18" filter="url(#shadow)"/>
    <rect x="-330" y="-225" width="660" height="440" rx="18" fill="${cover}"/>
    <rect x="-310" y="-210" width="305" height="410" rx="8" fill="${C.cream}"/>
    <rect x="5" y="-210" width="305" height="410" rx="8" fill="${C.cream}"/>
    <rect x="-6" y="-210" width="12" height="410" fill="#E8DCCD"/>`;
  for (const side of [-1, 1]) {
    for (let i = 0; i < 9; i++) {
      const lx = side < 0 ? -285 : 30;
      const w = 170 + r() * 90;
      s += `<path d="M${lx} ${-170 + i * 40} q ${f(w / 4)} -6 ${f(w / 2)} 0 t ${f(w / 2)} 0" stroke="${C.plumSoft}" stroke-width="4" fill="none" opacity="0.45" stroke-linecap="round"/>`;
    }
  }
  s += `<rect x="-340" y="-40" width="14" height="300" rx="4" fill="${C.peachDeep}" opacity="0.9"/></g>`;
  return s;
}

// ---------------------------------------------------------------------------
// Today, 8:12, happy — morning walk in the park; the maples are just starting to turn.
function autumnPark() {
  const r = rng(11);
  const defs =
    grad("sky", [[0, "#FCE7D6"], [0.55, "#FFF1E4"], [1, C.cream]]) +
    grad("lawn", [[0, C.sageLight], [1, C.sage]]) +
    grad("path", [[0, "#F3E3D3"], [1, "#E8CDB6"]]) +
    radial("sun", [[0, "#FFE2B8", 0.95], [1, "#FFE2B8", 0]]);
  const foliage = [C.amber, C.peachDeep, C.rust, C.gold, "#D9793F"];
  let body = `<rect width="${W}" height="${H}" fill="url(#sky)"/>
  <circle cx="1180" cy="260" r="380" fill="url(#sun)"/>
  <path d="${ridge(r, 690, 30, 8)}" fill="${C.lavenderLight}" opacity="0.7"/>
  <path d="${ridge(r, 760, 22, 7)}" fill="${C.sageLight}"/>
  <rect y="800" width="${W}" height="400" fill="url(#lawn)"/>
  <path d="M640 1200 C 760 1000, 900 900, 1010 800 L 1080 800 C 1020 900, 980 1020, 1010 1200 Z" fill="url(#path)"/>`;
  // Distant trees, some still green
  for (let i = 0; i < 9; i++) {
    const x = 60 + i * 190 + r() * 40;
    const y = 740 + r() * 30;
    const fill = i % 3 === 0 ? C.sage : foliage[i % foliage.length];
    body += `<rect x="${f(x - 6)}" y="${f(y)}" width="12" height="70" rx="6" fill="${C.plumSoft}" opacity="0.55"/>
    <circle cx="${f(x)}" cy="${f(y - 20)}" r="${f(55 + r() * 25)}" fill="${fill}" opacity="0.75"/>`;
  }
  // Main maple
  body += `<path d="M220 1200 C 250 1000, 230 860, 300 700 C 340 610, 420 540, 520 470" stroke="${C.plum}" stroke-width="54" fill="none" stroke-linecap="round"/>
  <path d="M300 720 C 220 620, 160 560, 60 520" stroke="${C.plum}" stroke-width="30" fill="none" stroke-linecap="round"/>
  <path d="M420 560 C 520 480, 640 420, 820 380" stroke="${C.plum}" stroke-width="22" fill="none" stroke-linecap="round"/>
  <path d="M520 470 C 560 380, 600 300, 700 220" stroke="${C.plum}" stroke-width="18" fill="none" stroke-linecap="round"/>
  <path d="M640 420 C 720 360, 820 330, 980 320" stroke="${C.plum}" stroke-width="12" fill="none" stroke-linecap="round"/>`;
  const crowns = [[120, 470, 170], [330, 420, 200], [560, 330, 210], [760, 260, 170], [880, 350, 150], [470, 560, 150], [660, 420, 130], [1000, 320, 110]];
  crowns.forEach(([cx, cy, rad], i) => {
    body += `<circle cx="${cx}" cy="${cy}" r="${rad}" fill="${i % 2 ? C.amber : "#E9954B"}" opacity="0.92"/>`;
  });
  for (const [cx, cy, rad] of crowns) {
    for (let i = 0; i < 18; i++) {
      const a = r() * Math.PI * 2;
      const d = r() * rad * 0.95;
      body += leaf(cx + Math.cos(a) * d, cy + Math.sin(a) * d, 26 + r() * 18, r() * 360, foliage[Math.floor(r() * foliage.length)]);
    }
  }
  // Falling leaves
  for (let i = 0; i < 40; i++) body += leaf(r() * W, 320 + r() * 860, 16 + r() * 12, r() * 360, foliage[Math.floor(r() * foliage.length)]);
  // Bench with a takeaway coffee
  body += `<g>
    <rect x="1090" y="900" width="420" height="26" rx="10" fill="${C.plumSoft}"/>
    <rect x="1090" y="940" width="420" height="26" rx="10" fill="${C.plumSoft}"/>
    <rect x="1110" y="966" width="18" height="120" rx="6" fill="${C.plum}"/>
    <rect x="1470" y="966" width="18" height="120" rx="6" fill="${C.plum}"/>
    <rect x="1090" y="840" width="420" height="22" rx="10" fill="${C.plumSoft}" opacity="0.9"/>
    <ellipse cx="1270" cy="902" rx="70" ry="12" fill="${C.plum}" opacity="0.25"/>
    <path d="M1225 790 L1315 790 L1304 900 L1236 900 Z" fill="#FFFFFF"/>
    <rect x="1216" y="778" width="108" height="20" rx="8" fill="${C.sageDeep}"/>
    <rect x="1230" y="825" width="80" height="40" rx="6" fill="${C.peach}"/>
    <path d="M1255 750 C 1240 725, 1270 710, 1255 685" stroke="#FFFFFF" stroke-width="6" fill="none" stroke-linecap="round" opacity="0.8"/>
  </g>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Today, 8:40 — sat by the coffee-shop window with the journal open, watching people go by.
function journalWindow() {
  const r = rng(89);
  const defs =
    grad("wall", [[0, "#F8EDE3"], [1, "#F1E0D2"]]) +
    grad("glass", [[0, "#E6EEE9"], [1, "#F3EBDD"]]) +
    grad("ledge", [[0, "#C79F7C"], [1, "#A57C5B"]]) +
    grad("mug", [[0, C.sage], [1, C.sageDeep]], { x1: 0, y1: 0, x2: 1, y2: 0 }) +
    radial("coffee", [[0, "#E7C9A5"], [1, "#A56F45"]]);
  let body = `<rect width="${W}" height="${H}" fill="url(#wall)"/>
  <rect x="140" y="60" width="1320" height="620" rx="24" fill="url(#glass)"/>`;
  // Street outside: turning trees and passers-by
  for (let i = 0; i < 6; i++) body += `<circle cx="${f(220 + i * 240 + r() * 40)}" cy="${f(420 + r() * 40)}" r="${f(110 + r() * 40)}" fill="${[C.amber, C.sageLight, C.peach][i % 3]}" opacity="0.7" filter="url(#soft)"/>`;
  for (const [px, c] of [[420, C.plumSoft], [520, C.peachDeep], [1080, C.sageDeep]]) {
    body += `<g opacity="0.55" filter="url(#soft)"><circle cx="${px}" cy="470" r="26" fill="${c}"/><rect x="${px - 30}" y="500" width="60" height="150" rx="28" fill="${c}"/></g>`;
  }
  body += `<rect x="140" y="560" width="1320" height="120" fill="#D9CFC4" opacity="0.6"/>
  <rect x="140" y="60" width="1320" height="620" rx="24" fill="none" stroke="${C.plum}" stroke-width="28"/>
  <rect x="786" y="60" width="28" height="620" fill="${C.plum}"/>
  <path d="M260 110 L520 110 L300 400 L200 400 Z" fill="#FFFFFF" opacity="0.25"/>
  <path d="M900 110 L1080 110 L920 400 L860 400 Z" fill="#FFFFFF" opacity="0.2"/>`;
  // Table top
  body += `<rect x="0" y="670" width="${W}" height="80" fill="url(#ledge)"/><rect x="0" y="740" width="${W}" height="460" fill="#E9D7C6"/>`;
  // Open journal and pen
  body += journal(r, 1000, 960, -6);
  body += `<g transform="translate(1340 860) rotate(28)"><rect x="-10" y="0" width="20" height="260" rx="10" fill="${C.plum}"/><path d="M-10 260 L0 295 L10 260 Z" fill="${C.gold}"/></g>`;
  // Mug on a saucer
  body += dropShadow(420, 900, 190, 40);
  body += `<ellipse cx="420" cy="905" rx="200" ry="36" fill="#FFFFFF"/>
  <path d="M290 650 L550 650 L530 900 L310 900 Z" fill="url(#mug)"/>
  <path d="M548 700 C 640 700, 640 840, 536 840" stroke="${C.sageDeep}" stroke-width="30" fill="none"/>
  <ellipse cx="420" cy="650" rx="130" ry="30" fill="url(#coffee)"/>
  <path d="M420 632 C 390 632, 390 660, 420 668 C 450 660, 450 632, 420 632 Z" fill="#FFF3E2"/>
  <path d="M380 590 C 360 550, 400 530, 380 490" stroke="#FFFFFF" stroke-width="8" fill="none" stroke-linecap="round" opacity="0.7"/>
  <path d="M460 590 C 440 550, 480 530, 460 490" stroke="#FFFFFF" stroke-width="8" fill="none" stroke-linecap="round" opacity="0.5"/>`;
  // A maple leaf picked up on the walk
  body += leaf(160, 1080, 90, -30, C.rust) + leaf(200, 1100, 70, 20, C.amber);
  // Morning light
  body += `<g opacity="0.35" filter="url(#soft)"><path d="M-100 700 L700 700 L1100 1300 L300 1300 Z" fill="#FFF6DD"/></g>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Day 8, 18:40, happy — golden-hour macro of dew on a rose at the botanical gardens.
function goldenRose() {
  const r = rng(37);
  const defs =
    radial("bg", [[0, "#FFE7C4"], [0.5, "#F6C79C"], [1, "#C98B86"]], { cx: 0.7, cy: 0.3, r: 0.9 }) +
    radial("petal", [[0, "#F7B7C6"], [0.7, C.blushDeep], [1, "#C76A86"]], { cx: 0.4, cy: 0.35, r: 0.8 }) +
    radial("petalDark", [[0, "#E48AA3"], [1, "#9E4868"]], { cx: 0.5, cy: 0.4, r: 0.7 }) +
    radial("dew", [[0, "#FFFFFF", 0.95], [0.35, "#FFFFFF", 0.5], [1, "#FFFFFF", 0.05]], { cx: 0.35, cy: 0.3, r: 0.7 });
  let body = `<rect width="${W}" height="${H}" fill="url(#bg)"/>`;
  for (let i = 0; i < 26; i++) {
    body += `<circle cx="${f(r() * W)}" cy="${f(r() * H)}" r="${f(30 + r() * 90)}" fill="${r() > 0.5 ? "#FFF4DC" : C.lavenderLight}" opacity="${f(0.15 + r() * 0.3)}" filter="url(#soft)"/>`;
  }
  body += `<path d="M760 1200 C 780 1050, 740 920, 780 760" stroke="${C.sageDeep}" stroke-width="30" fill="none" stroke-linecap="round"/>
  <path d="M770 980 C 640 930, 520 960, 430 1040 C 560 1060, 680 1040, 770 980 Z" fill="${C.sage}"/>
  <path d="M770 980 C 650 990, 540 1010, 430 1040" stroke="${C.sageDeep}" stroke-width="5" fill="none"/>
  <path d="M775 900 C 900 820, 1030 830, 1120 900 C 1000 950, 880 950, 775 900 Z" fill="${C.sageDeep}"/>
  <path d="M775 900 C 900 880, 1000 885, 1120 900" stroke="${C.sage}" stroke-width="5" fill="none"/>`;
  const cx = 800, cy = 520;
  const rings = [[330, 7, "url(#petal)"], [260, 6, "url(#petalDark)"], [200, 6, "url(#petal)"], [140, 5, "url(#petalDark)"], [90, 4, "url(#petal)"]];
  rings.forEach(([rad, n, fill], ri) => {
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + ri * 0.5;
      const px = cx + Math.cos(a) * rad * 0.45;
      const py = cy + Math.sin(a) * rad * 0.4;
      body += `<ellipse cx="${f(px)}" cy="${f(py)}" rx="${f(rad * 0.62)}" ry="${f(rad * 0.5)}" fill="${fill}" stroke="#B85A78" stroke-opacity="0.35" stroke-width="3" transform="rotate(${f((a * 180) / Math.PI + 90)} ${f(px)} ${f(py)})"/>`;
    }
  });
  body += `<path d="M${cx - 40} ${cy} C ${cx - 40} ${cy - 50}, ${cx + 40} ${cy - 50}, ${cx + 36} ${cy + 4} C ${cx + 30} ${cy + 40}, ${cx - 20} ${cy + 36}, ${cx - 14} ${cy + 6}" stroke="#8E3B5A" stroke-width="7" fill="none" stroke-linecap="round"/>`;
  for (const [dx, dy, dr] of [[640, 420, 22], [960, 470, 28], [720, 650, 18], [890, 360, 16], [560, 560, 20], [1040, 610, 14], [540, 1010, 18], [980, 870, 16]]) {
    body += `<circle cx="${dx}" cy="${dy + 3}" r="${dr}" fill="#7A2E4C" opacity="0.25"/><circle cx="${dx}" cy="${dy}" r="${dr}" fill="url(#dew)"/><circle cx="${f(dx - dr * 0.35)}" cy="${f(dy - dr * 0.35)}" r="${f(dr * 0.25)}" fill="#FFFFFF"/>`;
  }
  body += `<g opacity="0.18"><path d="M1600 0 L1100 1200 L1250 1200 L1600 180 Z" fill="#FFF6E0"/><path d="M1600 260 L1300 1200 L1380 1200 L1600 420 Z" fill="#FFF6E0"/></g>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Day 11, 19:50, grateful — sunset from the rooftop, city lights starting to flicker on.
function rooftopSunset() {
  const r = rng(23);
  const defs =
    grad("sky", [[0, "#5B3F6E"], [0.35, "#B77AA0"], [0.62, C.peachDeep], [0.82, C.peach], [1, "#FFD9B8"]]) +
    radial("sunGlow", [[0, "#FFE9C7", 1], [0.4, "#FFC99A", 0.7], [1, "#FFC99A", 0]]) +
    grad("roof", [[0, "#2A1937"], [1, "#1D1226"]]);
  let body = `<rect width="${W}" height="${H}" fill="url(#sky)"/>
  <circle cx="800" cy="720" r="520" fill="url(#sunGlow)"/>
  <circle cx="800" cy="720" r="120" fill="#FFE3BF"/>`;
  for (const [x, y, w, c] of [[180, 300, 520, C.blush], [900, 250, 460, C.blushDeep], [420, 430, 600, C.peach], [1100, 470, 420, "#FFD2B0"], [100, 540, 380, C.blush]]) {
    body += `<rect x="${x}" y="${y}" width="${w}" height="${f(18 + r() * 12)}" rx="14" fill="${c}" opacity="0.75"/>`;
  }
  let x = 0;
  while (x < W) {
    const w = 60 + r() * 90;
    const h = 120 + r() * 220;
    body += `<rect x="${f(x)}" y="${f(820 - h)}" width="${f(w)}" height="${f(h + 400)}" fill="#7A5A86" opacity="0.8"/>`;
    x += w + 6;
  }
  x = -20;
  while (x < W) {
    const w = 110 + r() * 130;
    const h = 200 + r() * 300;
    const top = 900 - h;
    body += `<rect x="${f(x)}" y="${f(top)}" width="${f(w)}" height="${f(h + 400)}" fill="${C.plum}"/>`;
    if (r() > 0.6) body += `<rect x="${f(x + w / 2 - 3)}" y="${f(top - 60)}" width="6" height="60" fill="${C.plum}"/>`;
    for (let wy = top + 30; wy < 900; wy += 42) {
      for (let wx = x + 18; wx < x + w - 24; wx += 34) {
        if (r() > 0.62) body += `<rect x="${f(wx)}" y="${f(wy)}" width="16" height="22" rx="3" fill="${r() > 0.3 ? "#FFD79A" : "#FFF1C9"}" opacity="${f(0.7 + r() * 0.3)}"/>`;
      }
    }
    x += w + 10;
  }
  body += `<rect y="930" width="${W}" height="270" fill="url(#roof)"/><rect y="905" width="${W}" height="30" fill="#3A2449"/>`;
  for (let i = 0; i < 26; i++) body += `<rect x="${i * 64 + 10}" y="820" width="8" height="90" fill="#3A2449"/>`;
  body += `<rect y="812" width="${W}" height="12" rx="6" fill="#3A2449"/>`;
  body += `<path d="M0 640 Q 400 760 800 660 T 1600 650" stroke="#2A1937" stroke-width="3" fill="none"/>`;
  for (let i = 0; i <= 24; i++) {
    const t = i / 24;
    const lx = t * W;
    const ly = t < 0.5 ? 640 + Math.sin(t * 2 * Math.PI) * 70 : 660 + Math.sin((t - 0.5) * 2 * Math.PI) * -10;
    body += `<circle cx="${f(lx)}" cy="${f(ly + 14)}" r="22" fill="#FFE2A8" opacity="0.35" filter="url(#soft)"/><circle cx="${f(lx)}" cy="${f(ly + 14)}" r="9" fill="#FFF0C8"/>`;
  }
  body += `<path d="M1300 1080 L1440 1080 L1420 1190 L1320 1190 Z" fill="${C.peachDeep}"/>
  <path d="M1370 1080 C 1330 980, 1260 950, 1230 900" stroke="${C.sageDeep}" stroke-width="10" fill="none"/>
  <path d="M1370 1080 C 1400 970, 1460 930, 1500 880" stroke="${C.sageDeep}" stroke-width="10" fill="none"/>
  <ellipse cx="1240" cy="920" rx="46" ry="22" fill="${C.sage}" transform="rotate(-30 1240 920)"/>
  <ellipse cx="1300" cy="980" rx="50" ry="22" fill="${C.sageDeep}" transform="rotate(-20 1300 980)"/>
  <ellipse cx="1480" cy="900" rx="46" ry="22" fill="${C.sage}" transform="rotate(35 1480 900)"/>
  <ellipse cx="1420" cy="970" rx="50" ry="22" fill="${C.sageDeep}" transform="rotate(25 1420 970)"/>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Day 17, 15:10, calm — rainy afternoon: finished the book, then sketched in the notebook.
function rainyReading() {
  const r = rng(61);
  const defs =
    grad("wall", [[0, "#E7E2EE"], [1, "#D9D2E4"]]) +
    grad("rainSky", [[0, "#9FA7B8"], [1, "#C4C9D3"]]) +
    grad("sill", [[0, "#C9B9A8"], [1, "#B09E8C"]]) +
    radial("lamp", [[0, "#FFE6B0", 0.8], [1, "#FFE6B0", 0]]);
  let body = `<rect width="${W}" height="${H}" fill="url(#wall)"/>
  <rect x="200" y="70" width="1200" height="600" rx="20" fill="url(#rainSky)"/>`;
  // Blurry rooftops and trees through the rain
  body += `<path d="${ridge(r, 520, 40, 6, 670)}" fill="#8D93A5" opacity="0.6" filter="url(#soft)"/>`;
  for (let i = 0; i < 5; i++) body += `<circle cx="${f(300 + i * 250)}" cy="${f(560 + r() * 30)}" r="${f(90 + r() * 30)}" fill="${C.sageDeep}" opacity="0.45" filter="url(#soft)"/>`;
  // Rain streaks and drops on the glass
  for (let i = 0; i < 90; i++) {
    const x = 210 + r() * 1180, y = 80 + r() * 560;
    body += `<path d="M${f(x)} ${f(y)} l -8 ${f(26 + r() * 30)}" stroke="#FFFFFF" stroke-width="3" opacity="${f(0.3 + r() * 0.4)}" stroke-linecap="round"/>`;
  }
  for (let i = 0; i < 30; i++) {
    const x = 210 + r() * 1180, y = 80 + r() * 560, d = 6 + r() * 10;
    body += `<circle cx="${f(x)}" cy="${f(y)}" r="${f(d)}" fill="#FFFFFF" opacity="0.45"/><circle cx="${f(x - d * 0.3)}" cy="${f(y - d * 0.3)}" r="${f(d * 0.3)}" fill="#FFFFFF" opacity="0.8"/>`;
  }
  body += `<rect x="200" y="70" width="1200" height="600" rx="20" fill="none" stroke="${C.plum}" stroke-width="26"/>
  <rect x="787" y="70" width="26" height="600" fill="${C.plum}"/><rect x="200" y="360" width="1200" height="20" fill="${C.plum}"/>`;
  // Window seat with a blanket and cushion
  body += `<rect x="0" y="660" width="${W}" height="70" fill="url(#sill)"/><rect x="0" y="730" width="${W}" height="470" fill="#CFC3D8"/>`;
  body += `<path d="M0 760 C 300 720, 600 800, 900 760 L 900 1200 L 0 1200 Z" fill="${C.lavender}" opacity="0.8"/>`;
  for (let i = 0; i < 8; i++) body += `<path d="M${i * 110} 760 L ${i * 110 + 40} 1200" stroke="#FFFFFF" stroke-width="10" opacity="0.25"/>`;
  body += `<rect x="1140" y="730" width="320" height="200" rx="60" fill="${C.peach}"/>`;
  // The finished book, closed
  body += `<g transform="translate(300 870) rotate(-8)">${dropShadow(0, 0, 200, 130, 0.2)}<rect x="-200" y="-130" width="400" height="260" rx="10" fill="${C.sageDeep}"/><rect x="-190" y="-120" width="12" height="240" fill="${C.sage}"/><rect x="-90" y="-40" width="220" height="16" rx="8" fill="${C.cream}" opacity="0.8"/><rect x="-60" y="-10" width="160" height="10" rx="5" fill="${C.cream}" opacity="0.6"/></g>`;
  // Sketchbook with abstract patterns and a pencil
  body += `<g transform="translate(900 960) rotate(6)">${dropShadow(0, 0, 250, 170, 0.2)}<rect x="-250" y="-170" width="500" height="340" rx="10" fill="${C.cream}"/>`;
  for (let i = 0; i < 6; i++) body += `<circle cx="${f(-120 + (i % 3) * 120)}" cy="${f(-60 + Math.floor(i / 3) * 120)}" r="${f(30 + r() * 20)}" fill="none" stroke="${C.plumSoft}" stroke-width="4" opacity="0.6"/>`;
  body += `<path d="M-200 110 q 40 -40 80 0 t 80 0 t 80 0 t 80 0 t 80 0" stroke="${C.peachDeep}" stroke-width="5" fill="none"/>`;
  for (let i = -240; i <= 240; i += 40) body += `<circle cx="${i}" cy="-170" r="7" fill="#9A8FA6"/>`;
  body += `<rect x="-280" y="120" width="16" height="200" rx="8" fill="${C.plum}" transform="rotate(-30 -280 120)"/></g>`;
  // Tea with the tag hanging out
  body += dropShadow(1300, 1030, 100, 30) + `<ellipse cx="1300" cy="1035" rx="110" ry="26" fill="#FFFFFF"/><path d="M1220 900 L1380 900 L1370 1030 L1230 1030 Z" fill="${C.cream}"/><ellipse cx="1300" cy="900" rx="80" ry="18" fill="#E7C57F"/><path d="M1380 930 C 1440 930, 1440 1000, 1376 1000" stroke="${C.cream}" stroke-width="18" fill="none"/><path d="M1300 900 L 1300 820" stroke="#D8CFC4" stroke-width="3"/><rect x="1288" y="800" width="26" height="30" fill="${C.peachDeep}"/>`;
  body += `<circle cx="1500" cy="620" r="360" fill="url(#lamp)"/>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Day 23, 16:30, grateful — volunteering at the community garden: tomatoes, herbs, sunflowers.
function communityGarden() {
  const r = rng(71);
  const defs =
    grad("sky", [[0, "#DDE8F0"], [0.6, "#F7EEDF"], [1, "#FBE9D2"]]) +
    grad("soil", [[0, "#8A5E45"], [1, "#6B452F"]]) +
    radial("sun", [[0, "#FFE9BD", 0.9], [1, "#FFE9BD", 0]]);
  let body = `<rect width="${W}" height="${H}" fill="url(#sky)"/>
  <circle cx="1350" cy="180" r="360" fill="url(#sun)"/>
  <path d="${ridge(r, 560, 30, 7)}" fill="${C.sageLight}"/>
  <path d="${ridge(r, 640, 20, 8)}" fill="${C.sage}"/>`;
  // Picket fence
  for (let i = 0; i < 24; i++) body += `<path d="M${i * 70 + 10} 700 L${i * 70 + 10} 600 L${i * 70 + 35} 575 L${i * 70 + 60} 600 L${i * 70 + 60} 700 Z" fill="${C.cream}" opacity="0.9"/>`;
  body += `<rect x="0" y="620" width="${W}" height="16" fill="${C.cream}"/><rect x="0" y="670" width="${W}" height="16" fill="${C.cream}"/>`;
  // Sunflowers along the back
  const sunflower = (x, y, h, s) => {
    let g = `<path d="M${x} ${y} L${x + 10} ${y + h}" stroke="${C.sageDeep}" stroke-width="14"/>` + leaf(x + 5, y + h * 0.45, 90, 20, C.sage) + leaf(x + 5, y + h * 0.6, 90, 160, C.sageDeep);
    for (let i = 0; i < 16; i++) {
      g += `<ellipse cx="${x}" cy="${f(y - s * 0.75)}" rx="${f(s * 0.22)}" ry="${f(s * 0.5)}" fill="${i % 2 ? C.gold : "#F5D160"}" transform="rotate(${(i / 16) * 360} ${x} ${y})"/>`;
    }
    return g + `<circle cx="${x}" cy="${y}" r="${f(s * 0.45)}" fill="#6B4226"/><circle cx="${x}" cy="${y}" r="${f(s * 0.3)}" fill="#8A5A30"/>`;
  };
  for (const [x, y, h, s] of [[120, 380, 520, 90], [300, 300, 600, 110], [1300, 330, 570, 100], [1480, 400, 500, 85]]) body += sunflower(x, y, h, s);
  // Raised beds
  body += `<rect x="0" y="760" width="${W}" height="440" fill="${C.sageDeep}"/>`;
  for (const bx of [80, 840]) {
    body += `<rect x="${bx}" y="800" width="680" height="330" rx="16" fill="#B98A5E"/><rect x="${bx + 24}" y="824" width="632" height="282" rx="10" fill="url(#soil)"/>`;
  }
  // Tomato plants on stakes
  for (let i = 0; i < 3; i++) {
    const tx = 200 + i * 210;
    body += `<rect x="${tx - 5}" y="700" width="10" height="330" fill="#C9A37A"/>`;
    for (let j = 0; j < 7; j++) body += leaf(tx + (r() - 0.5) * 120, 760 + r() * 260, 60 + r() * 30, r() * 360, j % 2 ? C.sage : C.sageDeep);
    for (let j = 0; j < 4; j++) {
      const cx = tx + (r() - 0.5) * 110, cy = 800 + r() * 220;
      body += `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(22 + r() * 10)}" fill="${r() > 0.3 ? "#D9503A" : "#F08A4B"}"/><circle cx="${f(cx - 7)}" cy="${f(cy - 7)}" r="6" fill="#FFFFFF" opacity="0.4"/>`;
    }
  }
  // Herbs in the second bed
  for (let i = 0; i < 5; i++) {
    const hx = 920 + i * 120;
    for (let j = 0; j < 9; j++) body += leaf(hx, 1050, 50 + r() * 50, -150 + j * 15 + (r() - 0.5) * 10, j % 2 ? "#6FA36B" : "#93BF7E");
  }
  // Harvest basket and gloves
  body += dropShadow(1320, 1100, 160, 40) + `<path d="M1170 1010 L1470 1010 L1430 1150 L1210 1150 Z" fill="#C49A6C"/>`;
  for (let i = 0; i < 5; i++) body += `<path d="M1180 ${1030 + i * 24} L1460 ${1030 + i * 24}" stroke="#A67C52" stroke-width="5"/>`;
  body += `<path d="M1190 1010 C 1220 900, 1420 900, 1450 1010" stroke="#A67C52" stroke-width="14" fill="none"/>`;
  for (const [cx, cy, c] of [[1250, 995, "#D9503A"], [1300, 985, "#F08A4B"], [1350, 998, "#D9503A"], [1400, 990, "#D9503A"]]) body += `<circle cx="${cx}" cy="${cy}" r="30" fill="${c}"/>`;
  body += leaf(1270, 975, 70, -60, C.sage) + leaf(1380, 970, 70, -120, "#93BF7E");
  body += `<path d="M1500 1120 c 30 -40 70 -40 80 0 l -10 60 l -60 0 z" fill="${C.lavender}"/>`;
  return frame(defs, body);
}

// ---------------------------------------------------------------------------
// Day 37, 12:40, happy — solo hike to the waterfall trail.
function waterfallTrail() {
  const r = rng(53);
  const defs =
    grad("sky", [[0, C.lavenderLight], [0.6, "#EEF0F4"], [1, "#F3F6EF"]]) +
    grad("fall", [[0, "#FFFFFF"], [1, "#DCE8F2"]], { x1: 0, y1: 0, x2: 1, y2: 0 }) +
    grad("pool", [[0, "#A9C9D6"], [1, "#7FA7B8"]]) +
    grad("cliff", [[0, "#6E5A7C"], [1, C.plum]]);
  let body = `<rect width="${W}" height="${H}" fill="url(#sky)"/>
  <circle cx="1260" cy="220" r="80" fill="#FFF6E6"/>
  <path d="${ridge(r, 380, 90, 6)}" fill="${C.lavender}" opacity="0.55"/>
  <path d="${ridge(r, 470, 70, 7)}" fill="#9C8BBF" opacity="0.6"/>`;
  body += `<path d="M0 1200 L0 300 C 120 280, 260 320, 360 360 C 480 400, 560 380, 640 420 L 700 1200 Z" fill="url(#cliff)"/>
  <path d="M1600 1200 L1600 330 C 1480 320, 1340 360, 1220 390 C 1100 420, 1000 400, 920 430 L 880 1200 Z" fill="url(#cliff)"/>`;
  body += `<path d="M640 420 C 700 410, 860 410, 920 430 L 900 980 L 690 980 Z" fill="url(#fall)"/>`;
  for (let i = 0; i < 18; i++) {
    const x = 660 + r() * 240;
    body += `<path d="M${f(x)} ${f(430 + r() * 40)} L ${f(x + (r() - 0.5) * 20)} ${f(900 + r() * 60)}" stroke="#C4D8E8" stroke-width="${f(3 + r() * 5)}" stroke-linecap="round" opacity="0.8"/>`;
  }
  body += `<rect y="990" width="${W}" height="${H - 990}" fill="${C.sageDeep}"/>
  <ellipse cx="800" cy="1010" rx="420" ry="90" fill="url(#pool)"/>
  <ellipse cx="800" cy="975" rx="220" ry="60" fill="#FFFFFF" opacity="0.7" filter="url(#soft)"/>`;
  const pine = (x, y, s, c) =>
    `<g><rect x="${f(x - s * 0.06)}" y="${f(y)}" width="${f(s * 0.12)}" height="${f(s * 0.35)}" fill="${C.plum}"/>
    <path d="M${f(x)} ${f(y - s)} L${f(x + s * 0.32)} ${f(y - s * 0.45)} L${f(x + s * 0.18)} ${f(y - s * 0.45)} L${f(x + s * 0.42)} ${f(y)} L${f(x - s * 0.42)} ${f(y)} L${f(x - s * 0.18)} ${f(y - s * 0.45)} L${f(x - s * 0.32)} ${f(y - s * 0.45)} Z" fill="${c}"/></g>`;
  for (let i = 0; i < 7; i++) body += pine(40 + i * 90 + r() * 30, 700 + r() * 200, 220 + r() * 120, i % 2 ? C.sageDeep : C.sage);
  for (let i = 0; i < 6; i++) body += pine(1020 + i * 100 + r() * 30, 720 + r() * 200, 220 + r() * 120, i % 2 ? C.sage : C.sageDeep);
  body += `<path d="M300 1200 C 420 1120, 520 1100, 560 1060 L 620 1070 C 560 1120, 520 1160, 500 1200 Z" fill="#E8CDB6"/>`;
  body += `<rect x="560" y="880" width="480" height="120" rx="60" fill="#FFFFFF" opacity="0.5" filter="url(#softer)"/>
  <path d="M1000 200 q 20 -18 40 0 q 20 -18 40 0" stroke="${C.plum}" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M1120 260 q 14 -12 28 0 q 14 -12 28 0" stroke="${C.plum}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
  return frame(defs, body);
}

// File names are referenced by ScreenshotDataSeeder; keep them in sync.
const scenes = {
  "autumn-park": autumnPark,
  "journal-window": journalWindow,
  "golden-rose": goldenRose,
  "rooftop-sunset": rooftopSunset,
  "rainy-reading": rainyReading,
  "community-garden": communityGarden,
  "waterfall-trail": waterfallTrail,
};

mkdirSync(svgDir, { recursive: true });
rmSync(photoDir, { recursive: true, force: true });
mkdirSync(photoDir, { recursive: true });

for (const [name, draw] of Object.entries(scenes)) {
  writeFileSync(join(svgDir, `${name}.svg`), draw());
  // Quick Look renders SVG through WebKit but always produces a square thumbnail, so
  // letterbox the scene into a square canvas and crop the padding back off with sips.
  const squarePath = join(svgDir, `${name}.square.svg`);
  writeFileSync(
    squarePath,
    `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><image x="0" y="${(W - H) / 2}" width="${W}" height="${H}" xlink:href="${name}.svg"/></svg>`
  );
  execFileSync("qlmanage", ["-t", "-s", String(W), "-o", svgDir, squarePath], { stdio: "ignore" });
  const jpg = join(photoDir, `${name}.jpg`);
  execFileSync("sips", ["-c", String(H), String(W), "-s", "format", "jpeg", "-s", "formatOptions", "88", join(svgDir, `${name}.square.svg.png`), "--out", jpg], { stdio: "ignore" });
  console.log(`wrote ${jpg}`);
}

// The SVGs are only an intermediate step.
rmSync(svgDir, { recursive: true, force: true });
