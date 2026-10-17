// Dino Run (jumpAndRun): Rex runs a voxel trail in 2.5D. Physics, course
// generation and scoring follow lib/features/minigames/games/jump_and_run/
// jump_run_logic.dart exactly (the server checks distance vs. play time).
import * as THREE from 'three';
import { Rex } from '../rex.js';
import { VoxelGrid, hash3 } from '../voxel.js';
import { rng, mat, box, lights, voxelTree, skyBackdrop, fitCamera, toScreen } from './common.js';

const P = {
  speed: 10, gravity: 28, jumpV: 12, half: 0.35, height: 1.2, forgive: 0.1,
  maxH: 1.0, maxW: 1.4, invuln: 1.2, buffer: 0.15, hearts: 3,
};
P.airTime = (2 * P.jumpV) / P.gravity;
P.apex = (P.jumpV * P.jumpV) / (2 * P.gravity);
P.minGap = P.speed * P.airTime + P.maxW + 4;

function generateCourse(s, random) {
  const runLength = s.runLength;
  const [minGap, maxGap] = s.obstacleDensity === 1 ? [30, 45] : s.obstacleDensity === 3 ? [P.minGap, 24] : [20, 34];
  const obstacles = [];
  let x = 25 + random() * 5;
  while (x < runLength - 12) {
    obstacles.push({ x, w: 0.8 + random() * (P.maxW - 0.8), h: 0.5 + random() * (P.maxH - 0.5) });
    x += minGap + random() * (maxGap - minGap);
  }
  const count = s.collectibleCount;
  const start = 12, span = runLength - 8 - start;
  const stars = [];
  for (let i = 0; i < count; i++) {
    let sx = start + (span * (i + random() * 0.6)) / count;
    for (const o of obstacles) if (sx > o.x - 3 && sx < o.x + o.w + 3) sx = o.x + o.w + 3;
    stars.push({ id: i, x: Math.min(sx, runLength - 2), y: random() < 0.5 ? 2.0 : 0.6 });
  }
  return { runLength, obstacles, stars };
}

class Sim {
  constructor(course) {
    this.c = course;
    this.x = 0; this.y = 0; this.vy = 0; this.time = 0;
    this.hearts = P.hearts; this.hits = 0;
    this.invulnUntil = -1; this.jumpAt = -10;
    this.collected = new Set(); this.hitSet = new Set();
  }
  get onGround() { return this.y <= 0 && this.vy <= 0; }
  get finished() { return this.x >= this.c.runLength; }
  get failed() { return this.hearts <= 0; }
  get over() { return this.finished || this.failed; }
  get invulnerable() { return this.time < this.invulnUntil; }
  jump() {
    if (this.over) return false;
    if (this.onGround) { this.vy = P.jumpV; return true; }
    this.jumpAt = this.time;
    return false;
  }
  step(dt, events) {
    if (this.over || dt <= 0) return;
    this.time += dt;
    this.x = Math.min(this.c.runLength, this.x + P.speed * dt);
    if (!this.onGround || this.vy > 0) {
      this.vy -= P.gravity * dt;
      this.y += this.vy * dt;
      if (this.y <= 0) {
        this.y = 0; this.vy = 0;
        if (this.time - this.jumpAt <= P.buffer) { this.vy = P.jumpV; this.jumpAt = -10; events.jump = true; }
      }
    }
    const left = this.x - P.half, right = this.x + P.half;
    this.c.obstacles.forEach((o, i) => {
      if (o.x > right) return;
      const overlap = right > o.x && left < o.x + o.w;
      if (overlap && this.y < o.h - P.forgive && !this.invulnerable) {
        this.hearts--; this.hits++; this.hitSet.add(i);
        this.invulnUntil = this.time + P.invuln;
        events.hit = true;
      }
    });
    for (const st of this.c.stars) {
      if (this.collected.has(st.id)) continue;
      if (Math.abs(st.x - this.x) < 0.8 && st.y + 0.4 > this.y && st.y - 0.4 < this.y + P.height) {
        this.collected.add(st.id);
        (events.stars ||= []).push(st);
      }
    }
  }
  details() {
    const distance = Math.max(0, Math.min(this.c.runLength, Math.floor(this.x)));
    return { distance, runLength: this.c.runLength, collected: this.collected.size, collectibles: this.c.stars.length, hits: this.hits };
  }
}

function starMesh() {
  const g = new VoxelGrid();
  for (let a = 0; a < 5; a++) {
    const ang = (a / 5) * Math.PI * 2 - Math.PI / 2;
    for (let r = 0; r <= 4; r++) g.set(Math.round(Math.cos(ang) * r), Math.round(-Math.sin(ang) * r), 0, 0xffd23f);
  }
  g.box(-1, -1, 0, 1, 1, 0, 0xffe680);
  return g.build({ size: 0.11, jitter: 0.05, material: new THREE.MeshLambertMaterial({ emissive: 0x6a4a00 }) });
}

function obstacleMesh(o, kind) {
  // Visual matches the hitbox (w × h) so jumps feel fair.
  const S = 0.2;
  const nx = Math.max(2, Math.round(o.w / S)), ny = Math.max(2, Math.round(o.h / S));
  const g = new VoxelGrid();
  if (kind === 0) { // rock
    g.ellipsoid(nx / 2 - 0.5, 0, 0, nx / 2, ny, 2.6, (x, y, z) => (y < 0 ? null : hash3(x, y, z) > 0.6 ? 0x7d7f86 : 0x94969e));
  } else if (kind === 1) { // log
    g.box(0, 0, -2, nx - 1, ny - 1, 2, (x, y, z) => (z === -2 || z === 2 ? 0xc89b5c : y % 2 ? 0x7a4a24 : 0x8b5a2b));
  } else { // cactus-ish spiky bush
    g.box(Math.floor(nx / 2) - 1, 0, -1, Math.floor(nx / 2), ny - 1, 0, 0x3f9a3a);
    for (let y = 1; y < ny - 1; y += 2) { g.set(0, y, 0, 0x2f7a2c); g.set(nx - 1, y + 1, -1, 0x2f7a2c); }
    g.box(0, Math.floor(ny / 2), -1, nx - 1, Math.floor(ny / 2), 0, 0x4fb048);
  }
  const m = g.build({ size: S, material: mat(0xffffff) });
  m.position.set(o.x + S / 2, S / 2, 0);
  return m;
}

export class RunGame {
  constructor({ settings, seed, hud, sfx, onFinish }) {
    this.s = settings; this.hud = hud; this.sfx = sfx; this.onFinish = onFinish;
    this.course = generateCourse(settings, rng(seed));
    this.sim = new Sim(this.course);
    this.state = 'intro';
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x9fd6ff);
    this.scene.fog = new THREE.Fog(0x9fd6ff, 30, 70);
    this.camera = new THREE.PerspectiveCamera(40, innerWidth / innerHeight, 0.1, 200);
    this.sun = lights(this.scene);
    this.build();
    this.resize();
    hud.setTitle('jumpAndRun');
    this.updateHud();
  }

  build() {
    const sc = this.scene;
    // Ground treadmill: colours repeat every 12 m, so snapping by 12 is seamless.
    const g = new VoxelGrid();
    for (let x = 0; x < 84; x++) for (let z = -12; z <= 16; z++) {
      const path = z >= -1 && z <= 1;
      const h = hash3(x % 12, z, 3);
      g.set(x, 0, z, path ? (h > 0.5 ? 0xc9a36a : 0xb8915a) : h > 0.75 ? 0x63c94a : h > 0.3 ? 0x4fb03f : 0x45a137);
    }
    this.ground = g.build({ size: 1, jitter: 0.04, material: mat(0xffffff), shadow: false });
    this.ground.position.y = -0.5;
    sc.add(this.ground);

    this.backdrop = skyBackdrop(220, 70);
    this.backdrop.position.set(0, 18, -60);
    sc.add(this.backdrop);

    // Trees and bushes recycle along the trail.
    this.decor = [];
    for (let i = 0; i < 16; i++) {
      const t = voxelTree(0.9 + (i % 3) * 0.25, i);
      t.position.set(i * 6 - 20, 0, -4 - (i % 3) * 2.2);
      sc.add(t);
      this.decor.push(t);
    }

    this.course.obstacles.forEach((o, i) => sc.add(obstacleMesh(o, i % 3)));
    const proto = starMesh();
    this.starMeshes = this.course.stars.map((st) => {
      const m = proto.clone();
      m.position.set(st.x, st.y + 0.6, 0);
      sc.add(m);
      return m;
    });

    // Finish arch.
    const L = this.course.runLength;
    box(sc, 0.4, 4, 0.4, 0xffffff, L, 2, -2);
    box(sc, 0.4, 4, 0.4, 0xffffff, L, 2, 2);
    const c = document.createElement('canvas');
    c.width = 16; c.height = 4;
    const ctx = c.getContext('2d');
    for (let x = 0; x < 16; x++) for (let y = 0; y < 4; y++) { ctx.fillStyle = (x + y) % 2 ? '#111' : '#fff'; ctx.fillRect(x, y, 1, 1); }
    const tex = new THREE.CanvasTexture(c);
    tex.magFilter = THREE.NearestFilter;
    const banner = new THREE.Mesh(new THREE.BoxGeometry(0.3, 1, 4.4), new THREE.MeshLambertMaterial({ map: tex }));
    banner.position.set(L, 4.2, 0);
    sc.add(banner);

    this.rex = new Rex();
    this.rex.baseYaw = 0;
    this.rexGroup = new THREE.Group();
    this.rexGroup.add(this.rex.root);
    this.rexGroup.rotation.y = Math.PI / 2; // face +x
    this.rexGroup.scale.setScalar(0.42);
    this.rexGroup.position.set(-6, 0, 0);
    sc.add(this.rexGroup);
    this.rex.setMode('run');
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    this.portrait = innerWidth < innerHeight;
  }

  start() {
    // Rex trots in from the left, then a countdown.
    this.state = 'countdown';
    this.count = 3.2;
    this.hud.say('3', 900);
    this.lastSaid = 3;
  }

  updateHud() {
    const hearts = '❤️'.repeat(this.sim.hearts) + '🤍'.repeat(P.hearts - this.sim.hearts);
    this.hud.setStats(`<span class="hearts">${hearts}</span><span>⭐ ${this.sim.collected.size}/${this.course.stars.length}</span>`);
    this.hud.setProgress(this.sim.x / this.course.runLength);
  }

  pointer() {
    if (this.state !== 'play') return;
    if (this.sim.jump()) this.sfx.jump();
  }

  update(dt, t) {
    const sim = this.sim;
    if (this.state === 'countdown') {
      this.rexGroup.position.x = Math.min(0, this.rexGroup.position.x + dt * 8);
      if (this.rexGroup.position.x >= 0) this.rex.setMode('run');
      this.count -= dt;
      const n = Math.ceil(this.count - 0.2);
      if (n !== this.lastSaid && n >= 0) {
        this.lastSaid = n;
        this.hud.say(n > 0 ? String(n) : 'Run! Tap to jump', n > 0 ? 900 : 1200);
        this.sfx.tick();
      }
      if (this.count <= 0) { this.state = 'play'; this.startedAt = performance.now(); }
    } else if (this.state === 'play') {
      const events = {};
      let left = dt;
      while (left > 0) { const h = Math.min(left, 1 / 120); sim.step(h, events); left -= h; }
      if (events.jump) this.sfx.jump();
      if (events.hit) { this.sfx.hit(); this.shake = 0.35; this.hud.say(sim.hearts > 0 ? 'Ouch!' : '', 600); }
      for (const st of events.stars || []) {
        this.starMeshes[st.id].visible = false;
        this.sfx.star();
        const p = toScreen(this.camera, this.starMeshes[st.id].position);
        this.hud.floatText('+⭐', p.x, p.y);
      }
      this.rexGroup.position.set(sim.x, sim.y, 0);
      this.rex.setMode(sim.onGround ? 'run' : 'jump');
      this.rexGroup.visible = !sim.invulnerable || Math.floor(t * 12) % 2 === 0;
      this.updateHud();
      if (sim.over) this.end();
    } else if (this.state === 'done') {
      this.rexGroup.visible = true;
      if (this.sim.finished) this.rexGroup.position.x += dt * Math.max(0, 6 - (t - this.doneAt) * 6);
    }

    for (const m of this.starMeshes) m.rotation.y += dt * 3;
    this.rex.update(dt, t);

    // Camera: diagonal 2.5D view looking down the trail ahead of Rex.
    const rx = this.rexGroup.position.x;
    const target = new THREE.Vector3(rx + (this.portrait ? 2.4 : 5), 1.1, 0);
    const dir = this.portrait ? new THREE.Vector3(-0.5, 0.5, 1) : new THREE.Vector3(-0.3, 0.32, 1);
    fitCamera(this.camera, target, dir, this.portrait ? 6.2 : 17, this.portrait ? 7 : 7.5);
    if (this.shake > 0) { this.shake -= dt; this.camera.position.x += (Math.random() - 0.5) * this.shake; }

    const snap = Math.floor((rx - 24) / 12) * 12;
    this.ground.position.x = snap;
    for (const d of this.decor) if (d.position.x < rx - 24) d.position.x += 16 * 6;
    this.backdrop.position.x = rx * 0.85;
    this.sun.position.set(rx - 6, 14, 9);
    this.sun.target.position.set(rx, 0, 0);
  }

  end() {
    this.state = 'done';
    this.doneAt = performance.now() / 1000;
    const won = this.sim.finished;
    this.rex.setMode(won ? 'cheer' : 'sad');
    won ? this.sfx.win() : this.sfx.lose();
    this.hud.say(won ? 'Finish! 🏁' : 'Out of hearts!', 1400);
    const elapsedMs = Math.round(performance.now() - this.startedAt);
    const details = this.sim.details();
    setTimeout(() => this.onFinish({ details, completed: won, elapsedMs }), 1500);
  }

  dispose() {}
}
