// Shared plumbing for the care scenes (kitchen, backyard, bath, nurse):
// a base class with camera framing, timers, particles and hit tests, plus a
// few voxel props used by more than one scene.
import * as THREE from 'three';
import { Rex } from '../rex.js';
import { VoxelGrid, hash3 } from '../voxel.js';
import { mat, fitCamera, toScreen } from '../minigames/common.js';

export const CARE_INFO = {
  feed: { icon: '🍗', title: 'Kitchen', color: '#f08a24' },
  play: { icon: '⚽', title: 'Backyard', color: '#43a047' },
  wash: { icon: '🛁', title: 'Bath Time', color: '#2f9bd6' },
  medicine: { icon: '🩺', title: "Nurse's Office", color: '#e5484d' },
};

const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
const v3 = new THREE.Vector3();

export class CareScene {
  // ctx: { game, hud, sfx, onFinish(result) }
  constructor(ctx) {
    Object.assign(this, ctx);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(40, innerWidth / innerHeight, 0.1, 200);
    this.timers = [];
    this.particles = [];
    this.state = 'intro';
    this.t = 0;
    this.down = null; // active pointer drag
  }

  get sick() { return this.game.state.status === 'sick'; }
  idleMode() { return this.sick ? 'sick' : 'idle'; }

  // A Rex for this scene, in the child's current colour.
  makeRex(scale = 0.6) {
    const rex = new Rex();
    rex.baseYaw = 0;
    const group = new THREE.Group();
    group.add(rex.root);
    group.scale.setScalar(scale);
    this.scene.add(group);
    rex.setMode(this.idleMode());
    return { rex, group };
  }

  // Camera: frame a w×h window around `target`, seen from `dir`, with
  // separate sizes for portrait and landscape screens.
  // `landTarget` optionally aims landscape screens somewhere else (e.g. to
  // keep characters above a dialog card).
  frame(target, dir, portrait, landscape, landTarget) {
    this.view = { target, dir, portrait, landscape, landTarget };
    this.resize();
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    if (!this.view) return;
    const portrait = innerWidth < innerHeight;
    const [w, h] = portrait ? this.view.portrait : this.view.landscape;
    const target = !portrait && this.view.landTarget ? this.view.landTarget : this.view.target;
    fitCamera(this.camera, target, this.view.dir, w, h);
  }

  later(sec, fn) { this.timers.push({ t: sec, fn }); }

  // Runs fn(k) for k 0→1 over `sec` (eased), then `done`.
  tween(sec, fn, done) {
    const tw = { age: 0, sec, fn, done };
    (this.tweens ||= []).push(tw);
    return tw;
  }

  coach(text) { this.hud.setCoach(text); }

  // ------------------------------------------------------------ input

  pointer(x, y) {
    this.down = { x, y, sx: x, sy: y, t: performance.now(), dist: 0 };
    this.hud.moveCursor(x, y);
    this.hud.setCursorActive(true);
    this.onDown?.(x, y);
  }

  pointerMove(x, y) {
    this.hud.moveCursor(x, y);
    if (!this.down) return;
    const d = this.down;
    const step = Math.hypot(x - d.x, y - d.y);
    d.dist += step;
    d.x = x; d.y = y;
    this.onDrag?.(x, y, step);
  }

  pointerUp(x, y) {
    if (!this.down) return;
    const d = this.down;
    this.down = null;
    this.hud.setCursorActive(false);
    this.onUp?.(x, y, d);
  }

  act() {}

  // ------------------------------------------------------------ hit tests

  rayFrom(x, y) {
    ndc.set((x / innerWidth) * 2 - 1, -(y / innerHeight) * 2 + 1);
    ray.setFromCamera(ndc, this.camera);
    return ray;
  }

  hit(x, y, obj) {
    return this.rayFrom(x, y).intersectObject(obj, true)[0] || null;
  }

  // Where the tap ray crosses the horizontal plane y = h.
  groundPoint(x, y, h = 0) {
    const r = this.rayFrom(x, y).ray;
    if (Math.abs(r.direction.y) < 1e-4) return null;
    const k = (h - r.origin.y) / r.direction.y;
    return k > 0 ? r.origin.clone().addScaledVector(r.direction, k) : null;
  }

  // Where the tap ray crosses the vertical plane z = z0.
  planePointZ(x, y, z0) {
    const r = this.rayFrom(x, y).ray;
    if (Math.abs(r.direction.z) < 1e-4) return null;
    const k = (z0 - r.origin.z) / r.direction.z;
    return r.origin.clone().addScaledVector(r.direction, k);
  }

  screen(objOrVec) {
    const p = objOrVec.isVector3 ? objOrVec : objOrVec.getWorldPosition(v3);
    return toScreen(this.camera, p);
  }

  near(x, y, objOrVec, px) {
    const s = this.screen(objOrVec);
    return Math.hypot(s.x - x, s.y - y) < px;
  }

  // World position of the tip of Rex's snout (follows the jaw).
  mouth(rex, out = new THREE.Vector3()) {
    rex.jaw.updateWorldMatrix(true, false);
    return rex.jaw.localToWorld(out.set(0, -0.02, 0.6));
  }

  // Sticks `mesh` onto whatever part of Rex the ray hit, so it moves with him.
  stickOn(hit, mesh, worldSize) {
    const part = hit.object.parent;
    part.updateWorldMatrix(true, false);
    part.add(mesh);
    mesh.position.copy(part.worldToLocal(hit.point.clone()));
    const s = part.getWorldScale(v3).x;
    mesh.scale.setScalar(worldSize / s);
    return mesh;
  }

  // ------------------------------------------------------------ particles

  // opts: { v: Vector3, gravity, life, spin, shrink }
  spawn(mesh, opts = {}) {
    mesh.userData.p = { v: opts.v || new THREE.Vector3(), g: opts.gravity ?? 9, life: opts.life ?? 1, age: 0, spin: opts.spin ?? 0, shrink: opts.shrink ?? true, s0: mesh.scale.x };
    this.scene.add(mesh);
    this.particles.push(mesh);
    return mesh;
  }

  // Little cubes bursting from `pos`.
  burst(pos, color, n = 8, speed = 2.5, size = 0.08, life = 0.8) {
    for (let i = 0; i < n; i++) {
      const m = new THREE.Mesh(CUBE, mat(color));
      m.scale.setScalar(size);
      m.position.copy(pos);
      this.spawn(m, {
        v: new THREE.Vector3((Math.random() - 0.5) * speed, Math.random() * speed, (Math.random() - 0.5) * speed),
        life: life * (0.7 + Math.random() * 0.6), spin: 6,
      });
    }
  }

  // ------------------------------------------------------------ frame

  update(dt, t) {
    this.t = t;
    for (const tw of (this.tweens || []).slice()) {
      tw.age += dt;
      const k = Math.min(1, tw.age / tw.sec);
      tw.fn(k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
      if (k >= 1) { this.tweens.splice(this.tweens.indexOf(tw), 1); tw.done?.(); }
    }
    for (let i = this.timers.length - 1; i >= 0; i--) {
      const tm = this.timers[i];
      tm.t -= dt;
      if (tm.t <= 0) { this.timers.splice(i, 1); tm.fn(); }
    }
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const m = this.particles[i];
      const p = m.userData.p;
      p.age += dt;
      p.v.y -= p.g * dt;
      m.position.addScaledVector(p.v, dt);
      m.rotation.x += p.spin * dt;
      m.rotation.y += p.spin * 0.7 * dt;
      if (p.shrink) m.scale.setScalar(p.s0 * Math.max(0, 1 - p.age / p.life));
      if (p.age >= p.life) { this.scene.remove(m); this.particles.splice(i, 1); }
    }
    this.tick?.(dt, t);
  }

  finish(result) {
    if (this.state === 'done') return;
    this.state = 'done';
    this.hud.setCursor(null);
    this.onFinish(result);
  }

  dispose() {
    this.hud.setCursor(null);
  }
}

export const CUBE = new THREE.BoxGeometry(1, 1, 1);

// ------------------------------------------------------------ props

// Checkerboard floor plus back and side walls.
export function buildRoom(scene, { floorA, floorB, wall, trim, w = 16, d = 10, h = 7 }) {
  const g = new VoxelGrid();
  for (let x = -w / 2; x < w / 2; x++) for (let z = -d / 2; z < d / 2; z++) g.set(x, 0, z, (x + z) & 1 ? floorA : floorB);
  const floor = g.build({ size: 1, jitter: 0.03, material: mat(0xffffff), shadow: false });
  floor.position.y = -0.5;
  scene.add(floor);
  const back = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.4), mat(wall));
  back.position.set(0, h / 2, -d / 2);
  back.receiveShadow = true;
  scene.add(back);
  const skirt = new THREE.Mesh(new THREE.BoxGeometry(w, 0.5, 0.5), mat(trim));
  skirt.position.set(0, 0.25, -d / 2 + 0.1);
  scene.add(skirt);
  for (const side of [-1, 1]) {
    const s = new THREE.Mesh(new THREE.BoxGeometry(0.4, h, d), mat(wall));
    s.position.set(side * w / 2, h / 2, 0);
    s.receiveShadow = true;
    scene.add(s);
  }
}

export function box(parent, w, h, d, color, x, y, z) {
  const m = new THREE.Mesh(CUBE, mat(color));
  m.scale.set(w, h, d);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

// Roasted leg bone (drumstick). Returns the group; userData.meat is the
// material to tint while it cooks.
export function legBone() {
  const meatMat = new THREE.MeshLambertMaterial({ color: 0xf2a0a0 });
  const boneMat = mat(0xf4ecd8);
  const g = new THREE.Group();
  const meat = new VoxelGrid().ellipsoid(0, 0, 0, 3.2, 2.4, 2.4, 0xffffff).build({ size: 0.1, jitter: 0.08, material: meatMat });
  g.add(meat);
  const bone = new VoxelGrid().box(3, -0.5, -0.5, 7, 0.5, 0.5, 0xffffff);
  for (const y of [-1, 1]) bone.set(7, y, 0, 0xffffff).set(8, y, 0, 0xffffff);
  const b = bone.build({ size: 0.1, jitter: 0.04, material: boneMat });
  g.add(b);
  g.userData.meat = meatMat;
  return g;
}

export function ballMesh(radius = 0.22) {
  const g = new THREE.Group();
  const m = new THREE.Mesh(new THREE.IcosahedronGeometry(radius, 1), new THREE.MeshLambertMaterial({ color: 0xe5484d, flatShading: true }));
  m.castShadow = true;
  const band = new THREE.Mesh(new THREE.TorusGeometry(radius * 1.0, radius * 0.18, 4, 10), mat(0xffffff));
  band.rotation.x = Math.PI / 2;
  g.add(m, band);
  return g;
}

// A blocky nurse: legs, scrubs, arms (rotatable), head, hair and cap.
export function buildNurse() {
  const SK = 0xf1c7a0, SCRUB = 0x3cb7a8, SCRUB_D = 0x2a8f83, HAIR = 0x6b4226, WHITE = 0xffffff, RED = 0xe5484d;
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);
  for (const sx of [-0.17, 0.17]) {
    box(body, 0.26, 0.9, 0.3, SCRUB_D, sx, 0.45, 0);
    box(body, 0.28, 0.12, 0.38, 0x334155, sx, 0.06, 0.04);
  }
  box(body, 0.72, 0.9, 0.42, SCRUB, 0, 1.35, 0);
  box(body, 0.2, 0.18, 0.02, WHITE, 0.18, 1.55, 0.22); // pocket
  box(body, 0.06, 0.12, 0.03, RED, 0.18, 1.62, 0.23);
  const head = new THREE.Group();
  head.position.set(0, 1.85, 0);
  body.add(head);
  box(head, 0.56, 0.56, 0.52, SK, 0, 0.3, 0);
  box(head, 0.62, 0.2, 0.58, HAIR, 0, 0.6, -0.02);
  box(head, 0.62, 0.5, 0.14, HAIR, 0, 0.35, -0.24);
  box(head, 0.09, 0.09, 0.02, 0x1d2433, -0.12, 0.34, 0.27); // eyes
  box(head, 0.09, 0.09, 0.02, 0x1d2433, 0.12, 0.34, 0.27);
  box(head, 0.18, 0.05, 0.02, 0xc0504d, 0, 0.17, 0.27); // smile
  box(head, 0.08, 0.06, 0.02, 0xf2a0a0, -0.2, 0.24, 0.27);
  box(head, 0.08, 0.06, 0.02, 0xf2a0a0, 0.2, 0.24, 0.27);
  // Cap with a red cross.
  box(head, 0.46, 0.16, 0.36, WHITE, 0, 0.76, 0.02);
  box(head, 0.14, 0.04, 0.02, RED, 0, 0.77, 0.21);
  box(head, 0.04, 0.12, 0.02, RED, 0, 0.77, 0.21);
  const arms = [];
  for (const side of [-1, 1]) {
    const a = new THREE.Group();
    a.position.set(side * 0.46, 1.72, 0);
    box(a, 0.2, 0.45, 0.24, SCRUB, 0, -0.18, 0);
    box(a, 0.17, 0.4, 0.2, SK, 0, -0.6, 0);
    body.add(a);
    arms.push(a);
  }
  // Stethoscope round the neck.
  box(body, 0.04, 0.4, 0.04, 0x334155, -0.14, 1.6, 0.23);
  box(body, 0.04, 0.4, 0.04, 0x334155, 0.1, 1.6, 0.23);
  box(body, 0.1, 0.1, 0.05, 0x94a3b8, -0.14, 1.38, 0.24);
  root.userData = { body, head, arms };
  return root;
}

// Scatter of simple flowers on grass.
export function flowerDots(scene, area, n, seed = 3) {
  for (let i = 0; i < n; i++) {
    const x = (hash3(i, seed, 1) - 0.5) * area.w, z = area.z0 - hash3(i, seed, 2) * area.d;
    const c = [0xffd23f, 0xff7ab0, 0xffffff, 0xb39cf0][i % 4];
    box(scene, 0.14, 0.06, 0.14, c, x, 0.03, z);
  }
}
