// Shared minigame plumbing: seeded random, settings + scoring rules (mirror
// lib/core/models/mini_game*.dart and functions/src/minigames/plan.ts — the
// server re-validates every rewarded outcome), scene helpers and the HUD.
import * as THREE from 'three';
import { VoxelGrid, hash3 } from '../voxel.js';

export const GAMES = {
  jumpAndRun: { title: 'Dino Run', icon: '🦖', blurb: 'Run, jump the rocks, grab the stars!', color: '#43a047' },
  matchPairs: { title: 'Memory Match', icon: '🔍', blurb: 'Rex peeks first. Then find the pairs!', color: '#7b4fd6' },
  balloonPopper: { title: 'Balloon Pop', icon: '🎈', blurb: 'Pop balloons to drop bones for Rex!', color: '#e5397d' },
  memoryRun: { title: 'Dance Steps', icon: '🪩', blurb: 'Watch Rex dance, then copy the steps!', color: '#2455c9' },
};
export const GAME_IDS = Object.keys(GAMES);

// mulberry32: small, fast, seeded.
export function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  next.int = (n) => Math.floor(next() * n);
  next.bool = () => next() < 0.5;
  next.shuffle = (arr) => {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = next.int(i + 1);
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  };
  return next;
}

const readInt = (raw, min, max, fallback) =>
  typeof raw === 'number' && Number.isFinite(raw) ? Math.min(max, Math.max(min, Math.round(raw))) : fallback;
const section = (raw) => (raw && typeof raw === 'object' ? raw : {});

// Same ranges and defaults as MiniGameSettings (Dart) / plan.ts.
export function readSettings(gameId, raw = {}) {
  const m = section(raw[gameId]);
  switch (gameId) {
    case 'balloonPopper':
      return { targetCount: readInt(m.targetCount, 5, 40, 15), timeLimitSec: readInt(m.timeLimitSec, 15, 90, 30) };
    case 'matchPairs':
      return { pairs: readInt(m.pairs, 3, 10, 6), maxMisses: readInt(m.maxMisses, 1, 10, 3) };
    case 'jumpAndRun': {
      const durationSec = readInt(m.durationSec, 15, 90, 30);
      const collectibleFrequency = readInt(m.collectibleFrequency, 1, 3, 2);
      return {
        durationSec,
        obstacleDensity: readInt(m.obstacleDensity, 1, 3, 2),
        collectibleFrequency,
        runLength: durationSec * 10,
        collectibleCount: Math.min(60, Math.max(2, Math.floor((durationSec * collectibleFrequency) / 5))),
      };
    }
    case 'memoryRun': {
      const speed = readInt(m.speed, 1, 3, 2);
      return { targetLength: readInt(m.targetLength, 3, 25, 8), speed, stepMs: speed === 1 ? 900 : speed === 3 ? 450 : 650 };
    }
  }
  return {};
}

// Practice rounds (no XP) let the child pick a difficulty. Values go through
// readSettings, so they stay inside the same ranges as bonus games.
// Same numbers as DifficultyPreset in lib/core/models/mini_game_settings.dart;
// Medium matches the default settings.
export const DIFFICULTIES = [
  { id: 'easy', label: 'Easy', icon: '🐣' },
  { id: 'medium', label: 'Medium', icon: '🦖' },
  { id: 'hard', label: 'Hard', icon: '🔥' },
];
const PRACTICE = {
  easy: {
    balloonPopper: { targetCount: 10, timeLimitSec: 40 },
    matchPairs: { pairs: 4, maxMisses: 4 },
    jumpAndRun: { durationSec: 25, obstacleDensity: 1, collectibleFrequency: 3 },
    memoryRun: { targetLength: 5, speed: 1 },
  },
  medium: {
    balloonPopper: { targetCount: 15, timeLimitSec: 30 },
    matchPairs: { pairs: 6, maxMisses: 3 },
    jumpAndRun: { durationSec: 30, obstacleDensity: 2, collectibleFrequency: 2 },
    memoryRun: { targetLength: 8, speed: 2 },
  },
  hard: {
    balloonPopper: { targetCount: 25, timeLimitSec: 30 },
    matchPairs: { pairs: 8, maxMisses: 3 },
    jumpAndRun: { durationSec: 40, obstacleDensity: 3, collectibleFrequency: 2 },
    memoryRun: { targetLength: 15, speed: 3 },
  },
};
export const difficultyOf = (id) => DIFFICULTIES.find((d) => d.id === id) || DIFFICULTIES[1];
export function practiceSettings(gameId, difficulty) {
  return readSettings(gameId, { [gameId]: PRACTICE[difficultyOf(difficulty).id][gameId] });
}

export function readMultiplier(raw = {}) {
  const m = section(raw.multiplier);
  const minPct = readInt(m.minPct, 100, 150, 100);
  const maxPct = readInt(m.maxPct, minPct, 300, Math.max(200, minPct));
  const curve = ['gentle', 'balanced', 'challenging'].includes(m.curve) ? m.curve : 'balanced';
  return { minPct, maxPct, curve };
}

const ratio = (part, whole) => (whole <= 0 ? 0 : Math.min(1, Math.max(0, part / whole)));

export function performance(gameId, d) {
  switch (gameId) {
    case 'balloonPopper': return ratio(d.popped, d.target);
    case 'matchPairs': return ratio(d.matched, d.pairs);
    case 'jumpAndRun': return 0.7 * ratio(d.distance, d.runLength) + 0.3 * (d.collectibles <= 0 ? 1 : ratio(d.collected, d.collectibles));
    case 'memoryRun': return ratio(d.reached, d.target);
  }
  return 0;
}

// XpMultiplier.award (preview only; the server decides).
export function xpPreview(baseXp, perf, mult) {
  const exp = { gentle: 0.7, balanced: 1, challenging: 1.5 }[mult.curve] ?? 1;
  const p = Math.min(1, Math.max(0, perf || 0));
  const raw = mult.minPct + (mult.maxPct - mult.minPct) * Math.pow(p, exp);
  const pct = Math.min(mult.maxPct, Math.max(mult.minPct, Math.round(raw / 5) * 5));
  return { pct, xp: baseXp > 0 ? Math.floor((baseXp * pct + 50) / 100) : 0 };
}

// ---------------------------------------------------------------- 3D helpers

const matCache = new Map();
export function mat(color, extra) {
  const k = color + JSON.stringify(extra || {});
  if (!matCache.has(k)) matCache.set(k, new THREE.MeshLambertMaterial({ color, flatShading: true, ...extra }));
  return matCache.get(k);
}

export function box(parent, w, h, d, color, x, y, z, extra) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color, extra));
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

export function lights(scene, { sky = 0xbfe3ff, ground = 0x5a7a3a, sun = 2.4, hemi = 1.7 } = {}) {
  scene.add(new THREE.HemisphereLight(sky, ground, hemi));
  const s = new THREE.DirectionalLight(0xfff2dc, sun);
  s.position.set(-6, 14, 9);
  s.castShadow = true;
  s.shadow.mapSize.set(512, 512);
  Object.assign(s.shadow.camera, { left: -14, right: 14, top: 14, bottom: -14, near: 1, far: 50 });
  s.shadow.bias = -0.002;
  scene.add(s);
  scene.add(s.target);
  return s;
}

// A voxel tree (trunk + chunky crown) at size ~1.
export function voxelTree(scale = 1, seed = 1) {
  const g = new VoxelGrid().box(-1, 0, -1, 0, 5, 0, 0x7a4a24);
  g.ellipsoid(0, 8, 0, 4, 3.6, 4, (x, y, z) => (hash3(x + seed, y, z) > 0.7 ? 0x56b840 : y > 9 ? 0x4ca83a : 0x3d9233));
  return g.build({ size: 0.16 * scale, material: mat(0xffffff) });
}

// Pixel-art sky band with mountains and a volcano, used behind outdoor games.
export function skyBackdrop(width, height, palette = 'day') {
  const c = document.createElement('canvas');
  c.width = 160;
  c.height = 60;
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, 0, 60);
  g.addColorStop(0, palette === 'party' ? '#2a1a5e' : '#4aa6ee');
  g.addColorStop(1, palette === 'party' ? '#7a3fa0' : '#cbeeff');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 160, 60);
  const mountain = (cx, h, col) => {
    for (let y = 0; y < h; y++) {
      const half = Math.floor((h - y) * 1.3);
      ctx.fillStyle = y > h - 4 ? '#eef4ff' : col;
      ctx.fillRect(cx - half, 60 - y, half * 2, 1);
    }
  };
  for (let i = 0; i < 6; i++) mountain(15 + i * 28, 18 + ((i * 7) % 11), i % 2 ? '#7d93c9' : '#6a82bd');
  ctx.fillStyle = '#ffffff';
  for (const [x, y] of [[20, 10], [70, 6], [120, 13]]) { ctx.fillRect(x, y, 14, 3); ctx.fillRect(x + 3, y - 2, 7, 2); }
  const tex = new THREE.CanvasTexture(c);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(width, height), new THREE.MeshBasicMaterial({ map: tex, fog: false }));
  return m;
}

// Places a perspective camera so a w×h window around `target` is visible.
export function fitCamera(camera, target, dir, w, h) {
  const tan = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const dist = Math.max(w / (2 * tan * camera.aspect), h / (2 * tan));
  camera.position.copy(target).addScaledVector(dir.clone().normalize(), dist);
  camera.lookAt(target);
}

const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
export function pick(camera, x, y, objects) {
  ndc.set((x / window.innerWidth) * 2 - 1, -(y / window.innerHeight) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  return ray.intersectObjects(objects, true)[0] || null;
}

// Screen position (CSS px) of a world point.
const tmp = new THREE.Vector3();
export function toScreen(camera, v) {
  tmp.copy(v).project(camera);
  return { x: (tmp.x + 1) / 2 * window.innerWidth, y: (1 - tmp.y) / 2 * window.innerHeight };
}

// ---------------------------------------------------------------- HUD

export class GameHud {
  constructor(root) {
    this.root = root;
    this.stats = root.querySelector('#gameStats');
    this.msg = root.querySelector('#gameMsg');
    this.extra = root.querySelector('#gameExtra');
    this.progress = root.querySelector('#gameProgress');
    this.coachEl = root.querySelector('#gameCoach');
    this.toolsEl = root.querySelector('#gameTools');
    this.dialogEl = root.querySelector('#gameDialog');
    this.cursorEl = root.querySelector('#gameCursor');
  }

  // ---- care scenes

  setHeader(icon, title, color) {
    this.root.querySelector('#gameTitle').innerHTML = `<span>${icon}</span>${title}`;
    this.root.style.setProperty('--game-color', color);
  }

  // Persistent instruction under the top bar.
  setCoach(text) {
    if (!this.coachEl) return;
    if (this.coachEl.textContent === (text || '') && !this.coachEl.hidden === !!text) return;
    this.coachEl.textContent = text || '';
    this.coachEl.hidden = !text;
    this.coachEl.classList.remove('pop');
    void this.coachEl.offsetWidth;
    this.coachEl.classList.add('pop');
  }

  // Step chips at the bottom: [{ icon, label, state: 'done'|'now'|'todo' }].
  setTools(list) {
    if (!this.toolsEl) return;
    this.toolsEl.hidden = !list;
    this.toolsEl.innerHTML = (list || []).map((s) =>
      `<div class="tool ${s.state}"><span>${s.state === 'done' ? '✅' : s.icon}</span><small>${s.label}</small></div>`).join('');
  }

  // Speech card: { who, name, text, buttons: [{ label, act, kind }] } or null.
  setDialog(d) {
    if (!this.dialogEl) return;
    this.dialogEl.hidden = !d;
    if (!d) { this.dialogEl.innerHTML = ''; return; }
    const btns = (d.buttons || []).map((b) => `<button class="btn ${b.kind || ''}" data-game-act="${b.act}">${b.label}</button>`).join('');
    this.dialogEl.innerHTML = `<div class="dlg-who">${d.who || ''}</div>
      <div class="dlg-main">${d.name ? `<b>${d.name}</b>` : ''}<p>${d.text}</p>${btns ? `<div class="dlg-btns">${btns}</div>` : ''}</div>`;
    this.dialogEl.classList.remove('pop');
    void this.dialogEl.offsetWidth;
    this.dialogEl.classList.add('pop');
  }

  // A tool (emoji, or 'towel') that follows the finger; null hides it.
  setCursor(tool) {
    if (!this.cursorEl) return;
    this.cursorTool = tool;
    this.cursorEl.hidden = !tool;
    this.cursorEl.className = 'game-cursor' + (tool === 'towel' ? ' towel' : '');
    this.cursorEl.textContent = tool && tool !== 'towel' ? tool : '';
  }

  moveCursor(x, y) {
    if (!this.cursorEl || !this.cursorTool) return;
    this.cursorEl.style.left = x + 'px';
    this.cursorEl.style.top = y + 'px';
  }

  setCursorActive(on) {
    this.cursorEl?.classList.toggle('active', !!on);
  }

  clearCare() {
    this.setCoach('');
    this.setTools(null);
    this.setDialog(null);
    this.setCursor(null);
  }

  setTitle(gameId) {
    const g = GAMES[gameId];
    this.root.querySelector('#gameTitle').innerHTML = `<span>${g.icon}</span>${g.title}`;
    this.root.style.setProperty('--game-color', g.color);
  }

  setStats(html) {
    if (this.stats.innerHTML !== html) this.stats.innerHTML = html;
  }

  setProgress(fraction) {
    if (fraction == null) { this.progress.hidden = true; return; }
    this.progress.hidden = false;
    this.progress.firstElementChild.style.width = Math.max(0, Math.min(1, fraction)) * 100 + '%';
  }

  // Big centre message; `ms` 0 = until replaced.
  say(text, ms = 1200) {
    clearTimeout(this.msgTimer);
    this.msg.textContent = text;
    this.msg.hidden = !text;
    this.msg.classList.remove('pop');
    void this.msg.offsetWidth;
    this.msg.classList.add('pop');
    if (ms && text) this.msgTimer = setTimeout(() => (this.msg.hidden = true), ms);
  }

  setExtra(html) {
    this.extra.innerHTML = html || '';
    this.extra.hidden = !html;
  }

  floatText(text, x, y, cls = '') {
    const el = document.createElement('div');
    el.className = 'game-float ' + cls;
    el.textContent = text;
    el.style.left = x + 'px';
    el.style.top = y + 'px';
    this.root.append(el);
    setTimeout(() => el.remove(), 1000);
  }
}
