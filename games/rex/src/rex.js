// Rex: a jointed voxel T-rex (hips → body → head/jaw/eyes/arms, legs, 4-part
// tail) plus the fossil he turns into and the optional Ptero Pal.
import * as THREE from 'three';
import { VoxelGrid, jointPart } from './voxel.js';

const S = 0.1; // world units per voxel

const GREEN = 0x3fae3a;
const GREEN_DARK = 0x267a2a;
const GREEN_LIGHT = 0x63c94a;
const CREAM = 0xf3e7b5;
const BELLY = 0xe6d590;
const WHITE = 0xffffff;
const BLACK = 0x141414;
const CAP = 0x2f7be6; // matches the 🧢 store icon
const CAP_DARK = 0x1d55b0;

const skin = (x, y, z, nx, ny, nz) => {
  if (nz > 0.6 && ny < 0.5 && Math.abs(nx) < 0.5) return BELLY;
  if (ny > 0.72) return GREEN_DARK;
  if (ny > 0.35 && nz < -0.2) return GREEN_DARK;
  if (ny < -0.6) return GREEN_LIGHT;
  return GREEN;
};

const headSkin = (x, y, z, nx, ny) => {
  if (ny > 0.55) return GREEN_DARK;
  if (ny < -0.55) return CREAM;
  return Math.abs(nx) > 0.85 ? GREEN_LIGHT : GREEN;
};

// Adds a row of dark spikes along the centre line of a shape: on top when
// walking along z, on the back (most negative z) when walking along y.
function ridge(grid, from, to, axis = 'z', step = 2) {
  for (let i = from; i <= to; i += step) {
    let edge = null;
    for (let k = -40; k < 60; k++) {
      if (axis === 'z' ? grid.has(0, k, i) : grid.has(0, i, k)) {
        if (axis === 'z') edge = k; // keeps the highest y
        else if (edge === null) edge = k; // first (lowest) z
      }
    }
    if (edge === null) continue;
    if (axis === 'z') grid.set(0, edge + 1, i, GREEN_DARK);
    else grid.set(0, i, edge - 1, GREEN_DARK);
  }
}

export class Rex {
  constructor() {
    this.material = new THREE.MeshLambertMaterial({ color: 0xffffff });
    this.root = new THREE.Group();
    this.root.name = 'rex';
    this.mode = 'idle';
    this.modeTime = 0;
    this.blinkT = 2;
    this.lookYaw = 0;
    this.targetYaw = 0;
    this.sickTint = new THREE.Color(0.7, 0.84, 0.42);
    this.white = new THREE.Color(1, 1, 1);
    this.build();
  }

  build() {
    const m = this.material;
    const HIP = [0, 10, 0];

    // Body (pivots at the hips so breathing/leaning stays grounded).
    const body = new VoxelGrid()
      .ellipsoid(0, 14, 0.5, 5.6, 6.6, 5, skin)
      .ellipsoid(0, 10, -1, 5, 4, 5, skin);
    ridge(body, 8, 20, 'y', 2);
    this.body = jointPart(body, HIP, [0, 0, 0], S, m);
    this.root.add(this.body);

    // Head + snout.
    const NECK = [0, 19, 1];
    const head = new VoxelGrid().ellipsoid(0, 23.5, 2, 5.4, 4.6, 5, headSkin);
    head.box(-4, 20, 4, 4, 24, 9, (x, y, z) => {
      const corner = (Math.abs(x) === 4 && (y === 24 || z === 9)) || (y === 24 && z === 9 && Math.abs(x) >= 3);
      if (corner) return null;
      if (y === 20) return (z >= 7 && (x + 10) % 2 === 0) ? WHITE : CREAM;
      return y >= 23 ? GREEN_DARK : GREEN;
    });
    head.set(-2, 23, 9, BLACK).set(2, 23, 9, BLACK);
    // Brows.
    head.box(-4, 28, 5, -1, 28, 6, GREEN_DARK).box(1, 28, 5, 4, 28, 6, GREEN_DARK);
    for (let z = -2; z <= 6; z += 2) head.set(0, 28, z, GREEN_DARK);
    this.head = jointPart(head, NECK, HIP, S, m);
    this.head.scale.setScalar(1.3); // big cartoon head
    this.body.add(this.head);

    // Jaw.
    const JAW = [0, 20, 3];
    const jaw = new VoxelGrid().box(-3, 18, 2, 3, 19, 8, (x, y, z) => {
      if (Math.abs(x) === 3 && z === 8) return null;
      if (y === 19 && z >= 7 && (x + 11) % 2 === 0) return WHITE;
      return y === 18 ? BELLY : CREAM;
    });
    jaw.box(-4, 19, 2, -4, 19, 6, GREEN).box(4, 19, 2, 4, 19, 6, GREEN);
    this.jaw = jointPart(jaw, JAW, NECK, S, m);
    this.head.add(this.jaw);

    // Eyes (separate so they can blink).
    this.eyes = [];
    for (const side of [-1, 1]) {
      const EYE = [side * 3, 26, 7];
      const lo = Math.min(side * 2, side * 4), hi = Math.max(side * 2, side * 4);
      const eye = new VoxelGrid().box(lo, 25, 7, hi, 27, 7, WHITE);
      const pIn = side * 2, pOut = side * 3;
      eye.box(Math.min(pIn, pOut), 25, 8, Math.max(pIn, pOut), 26, 8, BLACK);
      eye.set(pOut, 26, 8, WHITE);
      const g = jointPart(eye, EYE, NECK, S, this.material);
      g.children[0].castShadow = false;
      this.head.add(g);
      this.eyes.push(g);
    }

    // Arms.
    this.arms = [];
    for (const side of [-1, 1]) {
      const A = [side * 5, 15, 3];
      const arm = new VoxelGrid()
        .box(Math.min(side * 5, side * 6), 12, 3, Math.max(side * 5, side * 6), 15, 4, GREEN)
        .box(Math.min(side * 5, side * 6), 11, 5, Math.max(side * 5, side * 6), 11, 5, CREAM);
      const g = jointPart(arm, A, HIP, S, m);
      this.body.add(g);
      this.arms.push(g);
    }

    // Legs (children of root, so the body can lean without moving feet).
    this.legs = [];
    for (const side of [-1, 1]) {
      const L = [side * 3.5, 9, 0];
      const x0 = side > 0 ? 2 : -6, x1 = side > 0 ? 6 : -2;
      const leg = new VoxelGrid()
        .ellipsoid(side * 4, 6.5, 0, 2.6, 3.6, 3, skin)
        .box(x0 + 1, 1, -1, x1 - 1, 4, 1, GREEN)
        .box(x0, 0, -1, x1, 0, 4, GREEN_DARK);
      for (let x = x0; x <= x1; x += 2) leg.set(x, 0, 5, CREAM);
      const g = jointPart(leg, L, [0, 0, 0], S, m);
      this.root.add(g);
      this.legs.push(g);
    }

    // Tail: chain of four segments, each child of the previous.
    const segs = [
      { p: [0, 10, -4], c: [0, 9, -6.5], r: [3.6, 3.2, 3.6] },
      { p: [0, 8.5, -9], c: [0, 7.5, -11], r: [2.7, 2.4, 2.8] },
      { p: [0, 7, -13], c: [0, 6.5, -14.5], r: [1.9, 1.7, 2] },
      { p: [0, 6, -16], c: [0, 6, -17.6], r: [1.2, 1.1, 1.7] },
    ];
    this.tail = [];
    let parent = this.body, parentPivot = HIP;
    for (const s of segs) {
      const g = new VoxelGrid().ellipsoid(...s.c, ...s.r, skin);
      ridge(g, Math.floor(s.c[2] - s.r[2]), Math.ceil(s.c[2] + s.r[2]), 'z', 2);
      const part = jointPart(g, s.p, parentPivot, S, m);
      parent.add(part);
      this.tail.push(part);
      parent = part;
      parentPivot = s.p;
    }

    // Red cap (store item).
    const hat = new VoxelGrid()
      .ellipsoid(0, 27.5, 1.5, 4.6, 2.2, 4.4, (x, y) => (y < 27 ? null : CAP))
      .box(-3, 27, 6, 3, 27, 9, CAP_DARK)
      .box(-1, 30, 1, 1, 30, 2, WHITE);
    this.hat = hat.build({ size: S, material: m, origin: NECK });
    this.hat.visible = false;
    this.head.add(this.hat);

    // Anchor above the head for speech bubbles.
    this.anchor = new THREE.Object3D();
    this.anchor.position.set(0, 1.2, 0.2);
    this.head.add(this.anchor);

    this.root.rotation.y = -0.3;
    this.baseYaw = -0.3;
  }

  setMode(mode) {
    if (this.mode === mode) return;
    this.mode = mode;
    this.modeTime = 0;
  }

  // Temporary action animation; falls back to `after` when done.
  play(mode, seconds, after) {
    this.setMode(mode);
    this.actionUntil = seconds;
    this.actionAfter = after;
  }

  lookAt(normX) {
    this.targetYaw = THREE.MathUtils.clamp(normX * 0.6, -0.6, 0.6);
  }

  update(dt, t) {
    this.modeTime += dt;
    if (this.actionUntil != null && this.modeTime > this.actionUntil) {
      const next = this.actionAfter || 'idle';
      this.actionUntil = null;
      this.setMode(next);
    }
    const mode = this.mode;
    const lerp = (a, b, k) => a + (b - a) * Math.min(1, k * dt);

    // Defaults each frame (lerped toward per-mode targets).
    let breathe = 0.025, breatheSpd = 2.2, tailAmp = 0.22, tailSpd = 2.2;
    let headPitch = Math.sin(t * 1.1) * 0.05, jawOpen = 0, bodyLean = 0;
    let hop = 0, sink = 0, eyeOpen = 1, shiver = 0, armSwing = Math.sin(t * 2.2) * 0.15;
    let tint = this.white;
    let legSwing = 0, armsUp = 0, sway = 0, holdArm = 0;

    if (mode === 'happy') {
      hop = Math.abs(Math.sin(this.modeTime * 9)) * 0.35;
      tailAmp = 0.55; tailSpd = 9; jawOpen = 0.35; armSwing = Math.sin(t * 18) * 0.6;
    } else if (mode === 'run') {
      const k = t * 16;
      legSwing = Math.sin(k) * 0.85;
      hop = Math.abs(Math.sin(k)) * 0.08;
      armSwing = Math.sin(k) * 0.8;
      tailAmp = 0.3; tailSpd = 16; headPitch = 0.08; bodyLean = 0.18; jawOpen = 0.15;
    } else if (mode === 'jump') {
      legSwing = 0; armsUp = 0.9; jawOpen = 0.35; tailAmp = 0.2; headPitch = -0.15;
    } else if (mode === 'lookUp') {
      headPitch = -0.85; bodyLean = -0.12; tailAmp = 0.3; tailSpd = 3; jawOpen = 0.2;
    } else if (mode === 'cheer') {
      hop = Math.abs(Math.sin(this.modeTime * 9)) * 0.4;
      armsUp = 1.4; jawOpen = 0.4; tailAmp = 0.6; tailSpd = 10; headPitch = -0.2;
    } else if (mode === 'sad') {
      headPitch = 0.45; bodyLean = 0.1; eyeOpen = 0.5; tailAmp = 0.05; tailSpd = 1; armSwing = 0;
    } else if (mode === 'dance') {
      hop = Math.abs(Math.sin(t * 6)) * 0.22;
      sway = Math.sin(t * 3) * 0.18;
      armsUp = 0.6 + Math.sin(t * 6) * 0.5; tailAmp = 0.5; tailSpd = 6; jawOpen = 0.2;
    } else if (mode === 'hold') {
      holdArm = 1.5; headPitch = 0.4; tailAmp = 0.2;
    } else if (mode === 'eat') {
      headPitch = 0.4 + Math.sin(t * 4) * 0.05;
      bodyLean = 0.25;
      jawOpen = Math.sin(this.modeTime * 14) > 0 ? 0.45 : 0.05;
      tailAmp = 0.4; tailSpd = 6;
    } else if (mode === 'play') {
      hop = Math.abs(Math.sin(this.modeTime * 6)) * 0.5;
      headPitch = -0.25; jawOpen = 0.3; tailAmp = 0.6; tailSpd = 10;
      armSwing = Math.sin(t * 14) * 0.7;
    } else if (mode === 'wash') {
      shiver = Math.sin(t * 40) * 0.04;
      eyeOpen = 0.15; tailAmp = 0.5; tailSpd = 12;
    } else if (mode === 'sleep') {
      sink = 0.75; bodyLean = 0.35; headPitch = 0.45; eyeOpen = 0.08;
      breathe = 0.05; breatheSpd = 1.1; tailAmp = 0.05; tailSpd = 0.8; armSwing = 0;
    } else if (mode === 'sick') {
      headPitch = 0.32 + Math.sin(t * 0.8) * 0.05;
      bodyLean = 0.12; eyeOpen = 0.45; tailAmp = 0.06; tailSpd = 0.9;
      breatheSpd = 1.3; shiver = Math.sin(t * 30) * 0.012; armSwing = 0;
      tint = this.sickTint;
    } else if (mode === 'sneeze') {
      const k = this.modeTime;
      headPitch = k < 0.5 ? -0.35 * (k / 0.5) : 0.45;
      jawOpen = k < 0.5 ? 0.3 : 0.1;
      tint = this.sickTint;
    }

    // Blink.
    this.blinkT -= dt;
    let blink = 1;
    if (this.blinkT < 0.12) blink = 0.1;
    if (this.blinkT < 0) this.blinkT = 2 + Math.random() * 3.5;
    for (const e of this.eyes) e.scale.y = lerp(e.scale.y, Math.min(eyeOpen, blink), 25);

    this.lookYaw = lerp(this.lookYaw, mode === 'sleep' ? 0 : this.targetYaw, 3);
    this.body.scale.y = 1 + Math.sin(t * breatheSpd) * breathe;
    this.body.rotation.x = lerp(this.body.rotation.x, bodyLean, 6);
    this.head.rotation.x = lerp(this.head.rotation.x, headPitch, 8);
    this.head.rotation.y = this.lookYaw;
    this.jaw.rotation.x = lerp(this.jaw.rotation.x, jawOpen, 18);
    this.arms[0].rotation.x = armSwing - armsUp * 1.6;
    this.arms[1].rotation.x = -armSwing - armsUp * 1.6 - holdArm;
    this.body.rotation.z = lerp(this.body.rotation.z, sway, 8);
    this.tail.forEach((seg, i) => {
      seg.rotation.y = Math.sin(t * tailSpd - i * 0.7) * tailAmp;
      seg.rotation.x = mode === 'sleep' ? 0.1 : -0.04 * i;
    });
    const legFold = mode === 'sleep' ? 0.9 : mode === 'jump' ? 0.7 : 0;
    this.legs.forEach((l, i) => {
      const target = -legFold + (i ? -legSwing : legSwing);
      l.rotation.x = legSwing ? target : lerp(l.rotation.x, target, 10);
    });
    this.root.position.y = lerp(this.root.position.y, hop - sink, hop ? 30 : 5);
    this.root.position.x = shiver;
    this.root.rotation.y = this.baseYaw;
    this.material.color.lerp(tint, Math.min(1, dt * 2));
  }
}

// Bone pile on a rock slab — what Rex becomes if neglected too long.
export function buildFossil() {
  const BONE = 0xeae2c8, BONE_D = 0xc9bf9f, ROCK = 0x8a7a66, ROCK_D = 0x6d604f, HOLE = 0x2b241d;
  const g = new VoxelGrid();
  g.ellipsoid(0, 0, 0, 15, 4, 10, (x, y, z) => (y < 0 ? null : (y >= 3 ? ROCK : ROCK_D)));
  const top = 4;
  for (let x = -12; x <= 8; x++) g.set(x, top, 0, x % 3 === 0 ? BONE_D : BONE);
  for (const x of [-6, -3, 0, 3]) {
    for (let z = -5; z <= 5; z++) {
      if (z === 0) continue;
      const lift = Math.round(2 - Math.abs(z) * 0.4);
      g.set(x, top + Math.max(0, lift), z, BONE);
    }
  }
  g.box(9, top, -3, 15, top + 3, 3, (x, y, z) => {
    if (x === 15 && Math.abs(z) === 3) return null;
    if (x >= 12 && y === top + 2 && Math.abs(z) === 3) return HOLE;
    if (x >= 13 && y === top) return BONE_D;
    return BONE;
  });
  for (let x = 10; x <= 15; x += 2) g.set(x, top - 0, 4, 0xffffff);
  for (let x = -13; x >= -22; x--) {
    const z = Math.round(Math.sin(x * 0.4) * 2);
    if (Math.abs(x) % 2 === 0) g.set(x, top - (x < -18 ? 1 : 0), z, BONE);
  }
  for (const [lx, lz] of [[-8, 6], [2, 6], [-8, -6], [2, -6]]) {
    g.box(lx, top, lz, lx + 3, top, lz, BONE);
    g.box(lx + 3, top, lz + Math.sign(lz), lx + 4, top, lz + Math.sign(lz), BONE_D);
  }
  const mesh = g.build({ size: 0.12, jitter: 0.08, material: new THREE.MeshLambertMaterial() });
  const grp = new THREE.Group();
  grp.add(mesh);
  grp.rotation.y = 0.25;
  return grp;
}

// Small purple pterodactyl that circles the room (Special Pet item).
export function buildPtero() {
  const P = 0x6a3fc0, PD = 0x4a2a8f, PL = 0xb39cf0, Y = 0xf2c84b;
  const mat = new THREE.MeshLambertMaterial();
  const root = new THREE.Group();
  const body = new VoxelGrid().ellipsoid(0, 0, 0, 1.6, 1.4, 3.2, (x, y) => (y < 0 ? PL : P));
  body.box(-1, 1, 3, 1, 2, 6, P).box(-1, 0, 6, 1, 0, 9, Y).set(0, 3, 2, PD).set(0, 4, 1, PD).set(0, 4, 0, PD);
  body.set(-1, 2, 5, BLACK).set(1, 2, 5, BLACK);
  root.add(body.build({ size: 0.08, material: mat }));
  const wings = [];
  for (const side of [-1, 1]) {
    const w = new VoxelGrid();
    for (let i = 1; i <= 9; i++) w.box(side * i, 0, -2 + Math.floor(i / 3), side * i, 0, 2 - Math.floor(i / 4), i > 7 ? PD : P);
    const g = new THREE.Group();
    g.add(w.build({ size: 0.08, material: mat }));
    root.add(g);
    wings.push(g);
  }
  root.userData.wings = wings;
  return root;
}
