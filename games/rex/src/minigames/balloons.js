// Balloon Pop (balloonPopper): Rex runs into a field and looks up at
// balloons carrying bones; every pop drops a bone. Release schedule and
// rules follow lib/features/minigames/games/balloon_popper/balloon_popper_logic.dart.
import * as THREE from 'three';
import { Rex } from '../rex.js';
import { VoxelGrid, hash3 } from '../voxel.js';
import { rng, mat, lights, voxelTree, skyBackdrop, fitCamera, toScreen } from './common.js';

const COLORS = [0xe5484d, 0x2f7be6, 0xf7b928, 0x22b35e, 0x9b59b6, 0xff7ab0];
const DEPTH = -3.2; // balloons rise in this plane, behind Rex

function schedule(s, random) {
  const target = s.targetCount, limit = s.timeLimitSec * 1000;
  const count = Math.ceil(target * 1.4), window = Math.round(limit * 0.8);
  const out = [];
  let lastX = -1;
  for (let i = 0; i < count; i++) {
    const slot = (window * i) / count;
    const jitter = random() * (window / count) * 0.8;
    let x = 0.1 + random() * 0.8;
    if (Math.abs(x - lastX) < 0.18) x = x > 0.5 ? x - 0.3 : x + 0.3;
    lastX = x;
    out.push({ id: i, x: Math.min(0.9, Math.max(0.1, x)), color: random.int(COLORS.length), appearAt: Math.round(slot + jitter), riseMs: 4500 + random.int(2500) });
  }
  return { target, limit, balloons: out };
}

function boneMesh() {
  const g = new VoxelGrid().box(-3, 0, 0, 3, 0, 0, 0xf4ecd8);
  for (const x of [-4, 4]) { g.set(x, 1, 0, 0xf4ecd8); g.set(x, -1, 0, 0xf4ecd8); }
  return g.build({ size: 0.09, jitter: 0.03, material: mat(0xffffff) });
}

export class BalloonGame {
  constructor({ settings, seed, hud, sfx, onFinish }) {
    this.s = settings; this.hud = hud; this.sfx = sfx; this.onFinish = onFinish;
    this.round = schedule(settings, rng(seed));
    this.popped = new Set();
    this.state = 'intro';
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x8fd0ff);
    this.scene.fog = new THREE.Fog(0x8fd0ff, 25, 60);
    this.camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.1, 200);
    lights(this.scene);
    this.build();
    this.resize();
    hud.setTitle('balloonPopper');
    this.updateHud(0);
  }

  build() {
    const sc = this.scene;
    const g = new VoxelGrid();
    for (let x = -24; x < 24; x++) for (let z = -16; z < 10; z++) {
      const h = hash3(x, z, 9);
      g.set(x, 0, z, h > 0.93 ? (h > 0.97 ? 0xffd23f : 0xff7ab0) : h > 0.6 ? 0x63c94a : h > 0.25 ? 0x4fb03f : 0x45a137);
    }
    const ground = g.build({ size: 0.75, jitter: 0.04, material: mat(0xffffff), shadow: false });
    ground.position.y = -0.38;
    sc.add(ground);
    const back = skyBackdrop(160, 50);
    back.position.set(0, 16, -40);
    sc.add(back);
    for (let i = 0; i < 9; i++) {
      const t = voxelTree(1.2 + (i % 3) * 0.3, i);
      t.position.set(-16 + i * 4 + (i % 2) * 1.5, 0, -9 - (i % 3) * 2);
      sc.add(t);
    }

    const ballGeo = new THREE.IcosahedronGeometry(0.62, 1);
    ballGeo.scale(1, 1.15, 1);
    const knotGeo = new THREE.ConeGeometry(0.12, 0.18, 6);
    const stringGeo = new THREE.CylinderGeometry(0.015, 0.015, 1.1, 4);
    const bone = boneMesh();
    this.items = this.round.balloons.map((b) => {
      const grp = new THREE.Group();
      const ball = new THREE.Mesh(ballGeo, new THREE.MeshLambertMaterial({ color: COLORS[b.color], flatShading: true, emissive: COLORS[b.color], emissiveIntensity: 0.12 }));
      ball.castShadow = true;
      const knot = new THREE.Mesh(knotGeo, ball.material);
      knot.position.y = -0.74; knot.rotation.x = Math.PI;
      const string = new THREE.Mesh(stringGeo, mat(0xffffff));
      string.position.y = -1.35;
      const bn = bone.clone();
      bn.position.y = -1.95;
      grp.add(ball, knot, string, bn);
      grp.visible = false;
      sc.add(grp);
      return { spec: b, grp, bone: bn, phase: hash3(b.id, 1, 2) * 6 };
    });
    this.falling = [];
    this.bits = [];
    this.pile = 0;

    this.rex = new Rex();
    this.rex.baseYaw = 0;
    this.rexGroup = new THREE.Group();
    this.rexGroup.add(this.rex.root);
    this.rexGroup.scale.setScalar(0.5);
    this.rexGroup.position.set(-9, 0, 1.2);
    this.rexGroup.rotation.y = Math.PI / 2;
    sc.add(this.rexGroup);
    this.rex.setMode('run');
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    const portrait = innerWidth < innerHeight;
    fitCamera(this.camera, new THREE.Vector3(0, 3.6, DEPTH + 1), new THREE.Vector3(0, 0.05, 1), portrait ? 7.5 : 13, portrait ? 13 : 8.4);
    // Visible area of the balloon plane: where they rise and how wide.
    const dist = this.camera.position.z - DEPTH;
    const halfH = Math.tan(THREE.MathUtils.degToRad(this.camera.fov / 2)) * dist;
    const halfW = halfH * this.camera.aspect;
    const cy = this.camera.position.y;
    this.area = { halfW: halfW * 0.82, bottom: cy - halfH - 2.4, top: cy + halfH + 1.2 };
  }

  start() {
    this.state = 'enter';
    this.enterT = 0;
  }

  updateHud(elapsed) {
    const left = Math.max(0, Math.ceil((this.round.limit - elapsed) / 1000));
    this.hud.setStats(`<span>🦴 ${Math.min(this.popped.size, this.round.target)}/${this.round.target}</span><span>⏱ ${left}s</span>`);
    this.hud.setProgress(1 - Math.min(1, elapsed / this.round.limit));
  }

  elapsed() { return this.state === 'play' ? performance.now() - this.startedAt : this.endedAt ?? 0; }

  pointer(x, y) {
    if (this.state !== 'play') return;
    const el = this.elapsed();
    // Nearest balloon to the tap, generously sized for small fingers.
    let best = null, bestD = Math.max(54, Math.min(innerWidth, innerHeight) * 0.09);
    for (const it of this.items) {
      if (!it.grp.visible) continue;
      const p = toScreen(this.camera, it.grp.position);
      const d = Math.hypot(p.x - x, p.y - y);
      if (d < bestD) { best = it; bestD = d; }
    }
    if (!best) return;
    this.pop(best, el);
  }

  pop(it, el) {
    if (this.popped.has(it.spec.id) || el >= this.round.limit) return;
    this.popped.add(it.spec.id);
    it.grp.visible = false;
    this.sfx.pop();
    const pos = it.grp.position.clone();
    // Confetti bits.
    for (let i = 0; i < 10; i++) {
      const b = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.12, 0.12), it.grp.children[0].material);
      b.position.copy(pos);
      b.userData.v = new THREE.Vector3((Math.random() - 0.5) * 6, Math.random() * 4, (Math.random() - 0.5) * 3);
      this.scene.add(b);
      this.bits.push(b);
    }
    // The bone drops to the ground.
    const bone = it.bone.clone();
    bone.position.copy(pos).add(new THREE.Vector3(0, -1.95, 0));
    bone.userData.vy = 0;
    bone.userData.spin = (Math.random() - 0.5) * 8;
    this.scene.add(bone);
    this.falling.push(bone);
    const s = toScreen(this.camera, pos);
    this.hud.floatText('+🦴', s.x, s.y);
    this.rex.play('cheer', 0.5, 'lookUp');
    if (this.popped.size >= this.round.target) this.end();
  }

  update(dt, t) {
    if (this.state === 'enter') {
      this.enterT += dt;
      const g = this.rexGroup;
      if (g.position.x < 0) {
        g.position.x = Math.min(0, g.position.x + dt * 9);
        this.rex.setMode('run');
      } else {
        g.rotation.y += (0 - g.rotation.y) * Math.min(1, dt * 6);
        if (Math.abs(g.rotation.y) < 0.05) {
          this.rex.setMode('lookUp');
          this.state = 'play';
          this.startedAt = performance.now();
          this.hud.say('Pop the balloons! 🎈', 1300);
        }
      }
    }

    const el = this.elapsed();
    if (this.state === 'play') {
      if (el >= this.round.limit) this.end();
      this.updateHud(el);
    }

    const a = this.area;
    for (const it of this.items) {
      if (this.popped.has(it.spec.id)) continue;
      const p = (el - it.spec.appearAt) / it.spec.riseMs;
      const on = this.state === 'play' && p >= 0 && p < 1;
      it.grp.visible = on;
      if (!on) continue;
      const x = (it.spec.x * 2 - 1) * a.halfW + Math.sin(t * 1.3 + it.phase) * 0.25;
      it.grp.position.set(x, a.bottom + (a.top - a.bottom) * p, DEPTH - (it.spec.id % 3) * 0.4);
      it.grp.rotation.z = Math.sin(t * 1.7 + it.phase) * 0.12;
    }

    for (let i = this.bits.length - 1; i >= 0; i--) {
      const b = this.bits[i];
      b.userData.v.y -= 12 * dt;
      b.position.addScaledVector(b.userData.v, dt);
      b.rotation.x += dt * 8;
      if (b.position.y < -1) { this.scene.remove(b); this.bits.splice(i, 1); }
    }
    for (const b of this.falling) {
      if (b.userData.landed) continue;
      b.userData.vy -= 14 * dt;
      b.position.y += b.userData.vy * dt;
      b.rotation.z += b.userData.spin * dt;
      if (b.position.y <= 0.08) {
        b.position.y = 0.08;
        b.rotation.set(-Math.PI / 2, 0, Math.random() * 3);
        b.userData.landed = true;
        this.sfx.tick();
      }
    }
    this.rex.update(dt, t);
  }

  end() {
    if (this.state === 'done') return;
    this.endedAt = this.elapsed();
    this.state = 'done';
    const popped = Math.min(this.popped.size, this.round.target);
    const won = this.popped.size >= this.round.target;
    this.updateHud(this.endedAt);
    this.rex.setMode(won ? 'cheer' : 'idle');
    won ? this.sfx.win() : this.sfx.tick();
    this.hud.say(won ? 'All the bones! 🦴' : 'Time\'s up!', 1400);
    for (const it of this.items) it.grp.visible = false;
    const details = { popped, target: this.round.target };
    setTimeout(() => this.onFinish({ details, completed: won, elapsedMs: Math.round(this.endedAt) }), 1600);
  }

  dispose() {}
}
