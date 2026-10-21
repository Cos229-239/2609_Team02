// Memory Match (matchPairs): Rex sweeps a magnifying glass over the cards
// once (each card peeks as the lens passes), then the child finds the pairs.
// Rules follow lib/features/minigames/games/match_pairs/match_pairs_logic.dart.
import * as THREE from 'three';
import { Rex } from '../rex.js';
import { VoxelGrid } from '../voxel.js';
import { rng, mat, box, lights, fitCamera, pick, toScreen } from './common.js';

const SYMBOLS = ['🐶', '🐱', '🦊', '🐼', '🐸', '🦁', '🐵', '🐧', '🦄', '🐢', '🐙', '🦋', '🐝', '🐞'];
const CW = 1.0, CD = 1.3, GAP = 0.22;

// `upright`: the face sits on the card's underside and is seen after the
// 180° flip, so its texture is turned around to read the right way up.
function cardTexture(draw, upright = false) {
  const c = document.createElement('canvas');
  c.width = 128; c.height = 166;
  const ctx = c.getContext('2d');
  draw(ctx, 128, 166);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  if (upright) {
    t.center.set(0.5, 0.5);
    t.rotation = Math.PI;
  }
  return t;
}

const backTex = () => cardTexture((ctx, w, h) => {
  ctx.fillStyle = '#5b3fd6'; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = '#7b5cf0'; ctx.fillRect(8, 8, w - 16, h - 16);
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 72px Fredoka, sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText('?', w / 2, h / 2 + 4);
  ctx.fillStyle = 'rgba(255,255,255,.25)';
  for (const [x, y] of [[24, 26], [104, 26], [24, 140], [104, 140]]) { ctx.beginPath(); ctx.arc(x, y, 9, 0, 7); ctx.fill(); }
});

const faceTex = (symbol) => cardTexture((ctx, w, h) => {
  ctx.fillStyle = '#fff7e6'; ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#f2c84b'; ctx.lineWidth = 8; ctx.strokeRect(4, 4, w - 8, h - 8);
  ctx.font = '78px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(symbol, w / 2, h / 2 + 4);
}, true);

function magnifier() {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.42, 0.08, 6, 16), mat(0x3a2a1a));
  const glass = new THREE.Mesh(new THREE.CircleGeometry(0.4, 16), new THREE.MeshBasicMaterial({ color: 0xbfe8ff, transparent: true, opacity: 0.35, side: THREE.DoubleSide }));
  const handle = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.6, 0.12), mat(0x8b5a2b));
  handle.position.set(0, -0.72, 0);
  g.add(ring, glass, handle);
  ring.castShadow = handle.castShadow = true;
  return g;
}

export class MemoryGame {
  constructor({ settings, seed, hud, sfx, onFinish }) {
    this.s = settings; this.hud = hud; this.sfx = sfx; this.onFinish = onFinish;
    const r = rng(seed);
    const chosen = r.shuffle([...SYMBOLS]).slice(0, settings.pairs);
    this.deck = r.shuffle([...chosen, ...chosen]);
    this.cols = this.deck.length <= 6 ? 3 : 4;
    this.rows = Math.ceil(this.deck.length / this.cols);
    this.matched = new Set(); this.faceUp = []; this.misses = 0; this.matchedPairs = 0;
    this.state = 'intro';

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x3b5a8e);
    this.camera = new THREE.PerspectiveCamera(40, innerWidth / innerHeight, 0.1, 100);
    lights(this.scene, { sky: 0xfff1d6, ground: 0x6b4a2b, hemi: 1.9, sun: 1.8 });
    const lamp = new THREE.PointLight(0xffd59a, 18, 14, 1.5);
    lamp.position.set(0, 5, 1);
    this.scene.add(lamp);
    this.build();
    this.resize();
    hud.setTitle('matchPairs');
    this.updateHud();
  }

  cardPos(i) {
    const c = i % this.cols, r = Math.floor(i / this.cols);
    const lastRowCount = this.deck.length - (this.rows - 1) * this.cols;
    const rowCols = r === this.rows - 1 ? lastRowCount : this.cols;
    const x = (c - (rowCols - 1) / 2) * (CW + GAP);
    const z = (r - (this.rows - 1) / 2) * (CD + GAP);
    return new THREE.Vector3(x, 0.84, z);
  }

  build() {
    const sc = this.scene;
    const tw = this.cols * (CW + GAP) + 0.9, td = this.rows * (CD + GAP) + 0.9;
    this.tableW = tw; this.tableD = td;
    // Room: plank floor + brick wall (same palette as Rex's room).
    const floor = new VoxelGrid();
    for (let x = -14; x < 14; x++) for (let z = -10; z < 10; z++) floor.set(x, -1, z, (x + 40) % 3 === 0 ? 0x9c5f2c : 0xb5733c);
    const fm = floor.build({ size: 0.6, jitter: 0.07, material: mat(0xffffff), shadow: false });
    fm.position.y = 0.3;
    sc.add(fm);
    box(sc, 20, 10, 0.5, 0x3e5f98, 0, 5, -td / 2 - 3.4);
    // Table.
    box(sc, tw, 0.2, td, 0xa8692f, 0, 0.7, 0);
    box(sc, tw + 0.2, 0.08, td + 0.2, 0x8b5a2b, 0, 0.58, 0);
    for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) box(sc, 0.25, 0.6, 0.25, 0x7b4b24, x * (tw / 2 - 0.3), 0.3, z * (td / 2 - 0.3));

    const back = new THREE.MeshLambertMaterial({ map: backTex() });
    const edge = mat(0xe8e0f8);
    this.cards = this.deck.map((sym, i) => {
      const face = new THREE.MeshLambertMaterial({ map: faceTex(sym) });
      // Box faces: +x -x +y -y +z -z. Face-down shows the back (+y).
      const m = new THREE.Mesh(new THREE.BoxGeometry(CW, 0.06, CD), [edge, edge, back, face, edge, edge]);
      m.castShadow = true;
      m.position.copy(this.cardPos(i));
      m.userData = { i, flip: 0, target: 0, lift: 0 };
      sc.add(m);
      return m;
    });

    this.rex = new Rex();
    this.rex.baseYaw = 0;
    this.rexGroup = new THREE.Group();
    this.rexGroup.add(this.rex.root);
    this.rexGroup.scale.setScalar(0.72);
    this.rexGroup.position.set(0, 0, -td / 2 - 1.05);
    sc.add(this.rexGroup);
    this.rex.setMode('idle');

    this.lens = magnifier();
    this.lensHome = new THREE.Vector3(0.95, 2.1, -td / 2 - 0.35);
    this.lens.position.copy(this.lensHome);
    sc.add(this.lens);
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    const portrait = innerWidth < innerHeight;
    const target = new THREE.Vector3(0, 1.25, -0.7);
    fitCamera(this.camera, target, new THREE.Vector3(0, portrait ? 1.15 : 0.95, 1), this.tableW + 0.3, this.tableD + (portrait ? 3.2 : 2.8));
  }

  start() {
    this.state = 'sweep';
    this.hud.say('Rex takes a peek… 🔍', 1600);
    this.rex.setMode('hold');
    // Snake path over every card, one time.
    this.path = [];
    for (let r = 0; r < this.rows; r++) {
      const idx = [];
      for (let c = 0; c < this.cols; c++) { const i = r * this.cols + c; if (i < this.deck.length) idx.push(i); }
      if (r % 2) idx.reverse();
      this.path.push(...idx);
    }
    this.sweepT = -0.6;
    this.peeked = new Set();
  }

  setFlip(i, up) { this.cards[i].userData.target = up ? 1 : 0; }

  updateHud() {
    const left = Math.max(0, this.s.maxMisses - this.misses);
    this.hud.setStats(`<span>🃏 ${this.matchedPairs}/${this.s.pairs}</span><span class="hearts" title="Misses left">${'🔍'.repeat(left)}${'▫️'.repeat(this.s.maxMisses - left)}</span>`);
    this.hud.setProgress(null);
  }

  pointer(x, y) {
    if (this.state !== 'play' || this.faceUp.length === 2) return;
    const hit = pick(this.camera, x, y, this.cards);
    if (!hit) return;
    const i = hit.object.userData.i;
    if (this.matched.has(i) || this.faceUp.includes(i)) return;
    this.sfx.flip();
    this.faceUp.push(i);
    this.setFlip(i, true);
    if (this.faceUp.length < 2) return;
    const [a, b] = this.faceUp;
    if (this.deck[a] === this.deck[b]) {
      this.matched.add(a); this.matched.add(b);
      this.faceUp = [];
      this.matchedPairs++;
      setTimeout(() => {
        this.sfx.star();
        for (const k of [a, b]) this.cards[k].userData.glow = 1;
        const p = toScreen(this.camera, this.cards[b].position);
        this.hud.floatText('Match!', p.x, p.y, 'good');
        this.rex.play('cheer', 1.0, 'idle');
      }, 250);
    } else {
      this.misses++;
      setTimeout(() => {
        this.sfx.bad();
        this.rex.play('sad', 0.9, 'idle');
        this.setFlip(a, false); this.setFlip(b, false);
        this.faceUp = [];
        this.updateHud();
        if (this.misses >= this.s.maxMisses) this.end();
      }, 900);
    }
    this.updateHud();
    if (this.matchedPairs === this.s.pairs) this.end();
  }

  update(dt, t) {
    if (this.state === 'sweep') {
      this.sweepT += dt;
      const per = 0.42;
      const k = this.sweepT / per;
      if (k >= 0 && k < this.path.length) {
        const i0 = this.path[Math.floor(k)];
        const i1 = this.path[Math.min(this.path.length - 1, Math.floor(k) + 1)];
        const f = k - Math.floor(k);
        const p = this.cardPos(i0).lerp(this.cardPos(i1), f < 0.6 ? 0 : (f - 0.6) / 0.4);
        this.lens.position.lerp(new THREE.Vector3(p.x, 1.55, p.z), Math.min(1, dt * 14));
        this.lens.rotation.set(-1.1, 0, Math.sin(t * 6) * 0.15);
        if (!this.peeked.has(i0) && f > 0.1) {
          this.peeked.add(i0);
          this.setFlip(i0, true);
          this.sfx.flip();
          setTimeout(() => this.setFlip(i0, false), 900);
        }
        this.rex.lookAt(p.x / (this.tableW / 2));
      } else if (k >= this.path.length + 2.4) {
        this.state = 'play';
        this.startedAt = performance.now();
        this.rex.setMode('idle');
        this.rex.lookAt(0);
        this.hud.say('Your turn! Find the pairs', 1500);
      } else if (k >= this.path.length) {
        this.lens.position.lerp(this.lensHome, Math.min(1, dt * 4));
        this.lens.rotation.set(0, 0, 0.3);
      }
    } else {
      this.lens.position.lerp(this.lensHome, Math.min(1, dt * 4));
      this.lens.rotation.set(0, 0, 0.3 + Math.sin(t * 2) * 0.05);
    }

    for (const c of this.cards) {
      const u = c.userData;
      u.flip += (u.target - u.flip) * Math.min(1, dt * 12);
      c.rotation.z = u.flip * Math.PI;
      c.position.y = 0.84 + Math.sin(u.flip * Math.PI) * 0.45 + (this.matched.has(u.i) ? 0.04 : 0);
      if (u.glow) {
        u.glow = Math.max(0, u.glow - dt * 1.2);
        c.scale.setScalar(1 + u.glow * 0.15);
      }
    }
    this.rex.update(dt, t);
  }

  end() {
    if (this.state === 'done') return;
    this.state = 'done';
    const won = this.matchedPairs === this.s.pairs;
    setTimeout(() => {
      this.rex.setMode(won ? 'cheer' : 'sad');
      won ? this.sfx.win() : this.sfx.lose();
      this.hud.say(won ? 'All pairs found! 🎉' : 'Out of guesses!', 1400);
      // Show the remaining cards so the child sees where they were.
      if (!won) this.cards.forEach((c, i) => this.setFlip(i, true));
    }, 400);
    const elapsedMs = Math.round(performance.now() - this.startedAt);
    const details = { matched: this.matchedPairs, pairs: this.s.pairs, misses: this.misses };
    setTimeout(() => this.onFinish({ details, completed: won, elapsedMs }), 1900);
  }

  dispose() {}
}
