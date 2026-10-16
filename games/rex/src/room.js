// Rex's bedroom: voxel floor/walls/rug/nest-bed, pixel-art window and
// posters (canvas textures, nearest-filtered), furniture and unlockable decor.
import * as THREE from 'three';
import { VoxelGrid, hash3 } from './voxel.js';

const matCache = new Map();
function mat(color, extra) {
  const k = color + JSON.stringify(extra || {});
  if (!matCache.has(k)) matCache.set(k, new THREE.MeshLambertMaterial({ color, flatShading: true, ...extra }));
  return matCache.get(k);
}

function blk(parent, w, h, d, color, x, y, z, extra) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color, extra));
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

function pixelTexture(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');
  draw(ctx, w, h);
  const tex = new THREE.CanvasTexture(c);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.userData.ctx = ctx;
  return tex;
}

const THEMES = {
  day: { sky: ['#4aa6ee', '#bfe7ff'], far: '#7d93c9', mid: '#5c7bb0', hill: '#4f9d3a', hill2: '#3f8530', cloud: '#ffffff', sun: '#fff3a0', stars: false },
  night: { sky: ['#0b1438', '#2a3b7a'], far: '#2c3768', mid: '#222c58', hill: '#1d4b2a', hill2: '#173d22', cloud: '#3a4a86', sun: '#f4f1d0', stars: true },
  sunset: { sky: ['#ff7a59', '#ffd38a'], far: '#a9617f', mid: '#7a4a78', hill: '#5c7a33', hill2: '#4a6428', cloud: '#ffe0c0', sun: '#fff1b0', stars: false },
};

function drawWindowScene(ctx, w, h, themeName) {
  const th = THEMES[themeName] || THEMES.day;
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, th.sky[0]);
  g.addColorStop(1, th.sky[1]);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  if (th.stars) {
    ctx.fillStyle = '#fff';
    for (let i = 0; i < 40; i++) ctx.fillRect(Math.floor(hash3(i, 1, 2) * w), Math.floor(hash3(i, 3, 4) * h * 0.6), 1, 1);
  }
  ctx.fillStyle = th.sun;
  ctx.fillRect(w - 18, 6, 7, 7);
  ctx.fillRect(w - 19, 7, 9, 5);
  // Clouds.
  ctx.fillStyle = th.cloud;
  for (const [cx, cy] of [[10, 9], [36, 5], [58, 14]]) {
    ctx.fillRect(cx, cy, 12, 3);
    ctx.fillRect(cx + 3, cy - 2, 6, 2);
  }
  // Stepped mountains.
  const mountain = (cx, base, height, color, snow) => {
    for (let y = 0; y < height; y++) {
      const half = Math.floor((height - y) * 1.15);
      ctx.fillStyle = snow && y > height - 4 ? '#eef4ff' : color;
      ctx.fillRect(cx - half, base - y, half * 2, 1);
    }
  };
  mountain(18, h - 12, 22, th.far, true);
  mountain(62, h - 12, 26, th.far, true);
  mountain(40, h - 10, 20, th.mid, false);
  // Volcano with lava top.
  ctx.fillStyle = '#6b4a3a';
  for (let y = 0; y < 18; y++) {
    const half = Math.floor((18 - y) * 1.3) + 3;
    ctx.fillRect(42 - half, h - 10 - y, half * 2, 1);
  }
  ctx.fillStyle = '#ff5a1f';
  ctx.fillRect(39, h - 29, 6, 2);
  ctx.fillStyle = '#ffb02e';
  ctx.fillRect(40, h - 30, 4, 1);
  // Hills + trees.
  ctx.fillStyle = th.hill;
  ctx.fillRect(0, h - 12, w, 12);
  ctx.fillStyle = th.hill2;
  for (let x = 0; x < w; x += 7) ctx.fillRect(x, h - 13 - (x % 3), 4, 2);
  for (const tx of [6, 20, 70, 76]) {
    ctx.fillStyle = '#6b4423';
    ctx.fillRect(tx, h - 16, 1, 4);
    ctx.fillStyle = th.hill2;
    ctx.fillRect(tx - 2, h - 20, 5, 4);
    ctx.fillRect(tx - 1, h - 22, 3, 2);
  }
}

function posterTexture(lines, kind) {
  return pixelTexture(48, 64, (ctx, w, h) => {
    ctx.fillStyle = '#c9a24a';
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#1e3157';
    ctx.fillRect(2, 2, w - 4, h - 4);
    ctx.fillStyle = '#e9e2c9';
    ctx.font = 'bold 8px monospace';
    ctx.textAlign = 'center';
    lines.forEach((l, i) => ctx.fillText(l, w / 2, 12 + i * 9));
    if (kind === 'grow') {
      ctx.fillStyle = '#9fb0c9';
      // Pixel dino silhouette + rising bars.
      ctx.fillRect(8, 38, 10, 6); ctx.fillRect(14, 33, 7, 6); ctx.fillRect(9, 44, 2, 6); ctx.fillRect(15, 44, 2, 6); ctx.fillRect(3, 40, 6, 2);
      ctx.fillStyle = '#e0b84a';
      [[26, 52, 4], [31, 48, 8], [36, 44, 12], [41, 38, 18]].forEach(([x, y, hh]) => ctx.fillRect(x, y, 3, hh));
    }
  });
}

export function buildRoom() {
  const room = new THREE.Group();
  const api = { group: room };

  // Floor: wooden planks in 0.5 voxels.
  const floor = new VoxelGrid();
  const PLANKS = [0xb5733c, 0xa4652f, 0xc07f46, 0x9c5f2c];
  for (let x = -18; x < 18; x++)
    for (let z = -12; z < 22; z++) {
      const plank = Math.floor((x + 18) / 2);
      const seam = (z + plank * 5) % 9 === 0;
      floor.set(x, -1, z, seam ? 0x7a4a22 : PLANKS[plank % PLANKS.length]);
    }
  const floorMesh = floor.build({ size: 0.5, jitter: 0.07, material: mat(0xffffff), shadow: false });
  floorMesh.position.y = 0.25;
  room.add(floorMesh);

  // Walls: blue brick, 0.5 voxels, with a window hole in the back wall.
  const brick = (x, y, z) => {
    const row = Math.floor(y);
    const col = Math.floor((x + z + (row % 2) * 1) / 2);
    const h = hash3(col, row, 7);
    return y <= 2 ? (y === 2 ? 0x8a5a2b : 0x6e4622) : (h < 0.33 ? 0x3e5f98 : h < 0.66 ? 0x36568c : 0x45679f);
  };
  const back = new VoxelGrid();
  for (let x = -18; x < 18; x++)
    for (let y = 0; y < 22; y++) {
      if (x >= -5 && x <= 4 && y >= 5 && y <= 13) continue;
      back.set(x, y, -13, brick(x, y, 0));
    }
  room.add(back.build({ size: 0.5, jitter: 0.05, material: mat(0xffffff), shadow: false }));
  for (const side of [-1, 1]) {
    const wall = new VoxelGrid();
    const wx = side < 0 ? -19 : 18;
    for (let z = -13; z < 10; z++) for (let y = 0; y < 22; y++) wall.set(wx, y, z, brick(0, y, z));
    room.add(wall.build({ size: 0.5, jitter: 0.05, material: mat(0xffffff), shadow: false }));
  }
  // Corner + ceiling beams.
  for (const x of [-9.1, 8.6]) blk(room, 0.5, 11, 0.5, 0x7b4b24, x, 5.2, -6.1);
  blk(room, 18, 0.5, 0.6, 0x7b4b24, 0, 10.6, -6.1);
  for (const x of [-6, -2, 2, 6]) blk(room, 0.4, 0.4, 14, 0x845228, x, 10.7, 0);

  // Window (pixel-art landscape behind the hole).
  api.windowTex = pixelTexture(80, 60, (ctx, w, h) => drawWindowScene(ctx, w, h, 'day'));
  const view = new THREE.Mesh(new THREE.PlaneGeometry(5.4, 4.4), new THREE.MeshBasicMaterial({ map: api.windowTex }));
  view.position.set(-0.25, 4.5, -6.9);
  room.add(view);
  const frame = 0x8b5a2b;
  blk(room, 5.6, 0.35, 0.5, frame, -0.25, 2.35, -6.35);
  blk(room, 5.6, 0.35, 0.5, frame, -0.25, 6.65, -6.35);
  blk(room, 0.35, 4.6, 0.5, frame, -2.95, 4.5, -6.35);
  blk(room, 0.35, 4.6, 0.5, frame, 2.45, 4.5, -6.35);
  blk(room, 0.2, 4.3, 0.3, frame, -0.25, 4.5, -6.4);
  blk(room, 5.4, 0.2, 0.3, frame, -0.25, 4.5, -6.4);
  blk(room, 6.2, 0.25, 0.9, 0x9b6631, -0.25, 2.2, -6.1); // sill
  api.setWindowTheme = (name) => {
    const ctx = api.windowTex.userData.ctx;
    drawWindowScene(ctx, 80, 60, name);
    api.windowTex.needsUpdate = true;
  };

  // Posters.
  const p1 = new THREE.Mesh(new THREE.PlaneGeometry(2.1, 2.8), new THREE.MeshLambertMaterial({ map: posterTexture(['SMALL', 'TASKS', 'BIG', 'ADVEN-', 'TURES']) }));
  p1.position.set(-5.4, 5.0, -6.2);
  room.add(p1);
  const p2 = new THREE.Mesh(new THREE.PlaneGeometry(2.1, 2.8), new THREE.MeshLambertMaterial({ map: posterTexture(['GROW', 'STRONGER'], 'grow') }));
  p2.position.set(4.9, 5.0, -6.2);
  room.add(p2);

  // Round rug (0.25 voxels, concentric rings with dithered edges).
  const rug = new VoxelGrid();
  const BLUE = 0x2b5fae, GREENR = 0x4f9a3a, BLUE_L = 0x3f78c8;
  for (let x = -18; x <= 18; x++)
    for (let z = -16; z <= 16; z++) {
      const r = Math.hypot(x, z * 1.15);
      if (r > 18) continue;
      const ring = Math.floor((r + (hash3(x, 0, z) - 0.5) * 1.6) / 3.2);
      rug.set(x, 0, z, ring % 2 === 0 ? (ring === 0 ? BLUE_L : BLUE) : GREENR);
    }
  const rugMesh = rug.build({ size: 0.25, jitter: 0.08, material: mat(0xffffff), shadow: false });
  rugMesh.position.y = -0.1;
  room.add(rugMesh);

  // Nest bed: torus-like rim around a cushion (0.2 voxels).
  const bed = new VoxelGrid();
  for (let x = -10; x <= 10; x++)
    for (let z = -10; z <= 10; z++)
      for (let y = 0; y <= 5; y++) {
        const d = Math.hypot(x, z * 1.1);
        const rim = (d - 8) ** 2 / 4.5 + (y - 2.2) ** 2 / 5 <= 1;
        const cushion = d < 7.5 && y <= 1;
        if (rim) bed.set(x, y, z, y >= 4 ? 0x4a7fd6 : 0x2c56a8);
        else if (cushion) bed.set(x, y, z, (Math.floor(x / 3) + Math.floor(z / 3)) % 2 ? 0x8fb6ee : 0x7aa5e6);
      }
  room.add(bed.build({ size: 0.2, jitter: 0.06, material: mat(0xffffff) }));

  // Desk (back left) with egg, books, lamp.
  const desk = new THREE.Group();
  desk.position.set(-6.2, 0, -4.8);
  blk(desk, 3.2, 0.25, 1.6, 0x9b6631, 0, 1.9, 0);
  for (const [x, z] of [[-1.4, -0.6], [1.4, -0.6], [-1.4, 0.6], [1.4, 0.6]]) blk(desk, 0.22, 1.9, 0.22, 0x7b4b24, x, 0.95, z);
  const egg = new VoxelGrid().ellipsoid(0, 0, 0, 3, 4, 3, (x, y, z) => (hash3(x, y, z) > 0.82 ? 0x6fbf5a : 0xf1f0e4));
  const eggMesh = egg.build({ size: 0.1, material: mat(0xffffff) });
  eggMesh.position.set(-0.8, 2.45, 0.1);
  desk.add(eggMesh);
  [[0x3b6fd1, 0.5], [0xd94b3d, 0.62], [0xe6b23a, 0.74]].forEach(([c, y], i) => blk(desk, 0.9, 0.12, 0.6, c, 0.6, 1.95 + 0.12 * (i + 1), 0));
  blk(desk, 0.1, 0.8, 0.1, 0x333333, 1.2, 2.5, -0.3);
  blk(desk, 0.5, 0.3, 0.4, 0x2f8f4a, 1.2, 2.95, -0.2);
  room.add(desk);

  // Bookshelf (back right).
  const shelf = new THREE.Group();
  shelf.position.set(6.6, 0, -5);
  blk(shelf, 2.4, 5.2, 0.2, 0x7b4b24, 0, 2.6, -0.5);
  blk(shelf, 0.2, 5.2, 1.1, 0x8b5a2b, -1.1, 2.6, 0);
  blk(shelf, 0.2, 5.2, 1.1, 0x8b5a2b, 1.1, 2.6, 0);
  const BOOKS = [0xd94b3d, 0x3b6fd1, 0xe6b23a, 0x58a84a, 0x9b59b6, 0xe67e22];
  for (let s = 0; s < 4; s++) {
    const y = 0.3 + s * 1.3;
    blk(shelf, 2.2, 0.15, 1.0, 0x9b6631, 0, y, 0);
    if (s === 2) continue; // space for the plush
    for (let b = 0; b < 6; b++) {
      const bh = 0.6 + hash3(s, b, 1) * 0.35;
      blk(shelf, 0.26, bh, 0.7, BOOKS[(s * 3 + b) % BOOKS.length], -0.8 + b * 0.3, y + 0.08 + bh / 2, 0);
    }
  }
  room.add(shelf);

  // Toy chest (right).
  const chest = new THREE.Group();
  chest.position.set(5.6, 0, -1.6);
  chest.rotation.y = -0.4;
  blk(chest, 2.2, 1.2, 1.3, 0x8b5a2b, 0, 0.6, 0);
  blk(chest, 2.3, 0.35, 1.4, 0x9b6631, 0, 1.35, 0);
  for (const x of [-0.7, 0.7]) blk(chest, 0.15, 1.6, 1.42, 0x3a3a3a, x, 0.8, 0);
  blk(chest, 0.3, 0.3, 0.1, 0xe6b23a, 0, 1.1, 0.7);
  room.add(chest);

  // Bean bag (front left).
  const bean = new VoxelGrid().ellipsoid(0, 3, 0, 8, 5, 7, (x, y) => (y > 5 ? 0x3466c2 : 0x2a56a8));
  const beanMesh = bean.build({ size: 0.15, material: mat(0xffffff) });
  beanMesh.position.set(-6, -0.4, 0.8);
  room.add(beanMesh);

  // Window-sill plant.
  room.add(potPlant(0.8, -1.9, 2.35, -6));

  // Food bowl (front right). `api.food` shows when Rex is fed.
  const bowl = new THREE.Group();
  bowl.position.set(2.9, 0, 2.4);
  const cup = new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.55, 0.4, 10, 1, true), mat(0x2d5bb5, { side: THREE.DoubleSide }));
  cup.position.y = 0.2;
  cup.castShadow = true;
  bowl.add(cup);
  blk(bowl, 1.0, 0.06, 1.0, 0x1d3f85, 0, 0.04, 0);
  const food = new VoxelGrid();
  for (let x = -5; x <= 5; x++) for (let z = -5; z <= 5; z++) if (x * x + z * z < 26) food.set(x, 0, z, hash3(x, 1, z) > 0.5 ? 0xb5532a : 0xd9773a);
  api.food = food.build({ size: 0.12, material: mat(0xffffff) });
  api.food.position.y = 0.32;
  api.food.visible = false;
  bowl.add(api.food);
  api.bowl = bowl;
  room.add(bowl);

  // Bone toy (front).
  const bone = new THREE.Group();
  bone.position.set(-2.3, 0.15, 3.1);
  bone.rotation.y = 0.5;
  blk(bone, 1.2, 0.22, 0.22, 0xeee6cf, 0, 0, 0);
  for (const x of [-0.65, 0.65]) for (const z of [-0.15, 0.15]) blk(bone, 0.3, 0.3, 0.3, 0xeee6cf, x, 0, z);
  room.add(bone);

  // Ball (owned item).
  const ballGeo = new THREE.IcosahedronGeometry(0.42, 1);
  const colors = [];
  const pos = ballGeo.attributes.position;
  for (let i = 0; i < pos.count; i += 3) {
    const y = (pos.getY(i) + pos.getY(i + 1) + pos.getY(i + 2)) / 3;
    const c = new THREE.Color(Math.abs(y) < 0.12 ? 0xffffff : 0x2f6fe0);
    for (let k = 0; k < 3; k++) colors.push(c.r, c.g, c.b);
  }
  ballGeo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  api.ball = new THREE.Mesh(ballGeo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
  api.ball.castShadow = true;
  api.ball.position.set(1.0, 0.42, 3.3);
  api.ballHome = api.ball.position.clone();
  api.ball.visible = false;
  room.add(api.ball);

  // Decor unlocks.
  api.decor = {};
  api.decor.plant = potPlant(1.6, -7.6, 0, 3.2);
  room.add(api.decor.plant);
  api.decor.plush = (() => {
    const g = new VoxelGrid()
      .ellipsoid(0, 3, 0, 2.5, 3, 2.2, 0x4fbf4a)
      .ellipsoid(0, 7, 1, 2.6, 2.2, 2.4, 0x4fbf4a)
      .set(-1, 7, 3, 0x111111).set(1, 7, 3, 0x111111)
      .box(-1, 2, 2, 1, 4, 2, 0xf3e7b5);
    const m = g.build({ size: 0.1, material: mat(0xffffff) });
    m.position.set(6.6, 2.95, -5);
    return m;
  })();
  room.add(api.decor.plush);
  api.decor.glowEgg = (() => {
    const grp = new THREE.Group();
    const g = new VoxelGrid().ellipsoid(0, 0, 0, 2.5, 3.4, 2.5, (x, y, z) => (hash3(x, y, z) > 0.7 ? 0x9ff5d5 : 0x5fe0b8));
    const m = g.build({ size: 0.1, material: new THREE.MeshLambertMaterial({ emissive: 0x2fbf96, emissiveIntensity: 0.9 }) });
    grp.add(m);
    const light = new THREE.PointLight(0x6fffd0, 2.5, 4, 1.6);
    grp.add(light);
    grp.position.set(-5.4, 2.4, -4.6);
    grp.userData.light = light;
    grp.userData.mesh = m;
    return grp;
  })();
  room.add(api.decor.glowEgg);
  for (const d of Object.values(api.decor)) d.visible = false;

  // Pendant lamp.
  const lamp = new THREE.Group();
  lamp.position.set(0, 9, 0.5);
  blk(lamp, 0.06, 1.6, 0.06, 0x222222, 0, 0.9, 0);
  const shade = new THREE.Mesh(new THREE.ConeGeometry(0.85, 0.7, 8, 1, true), mat(0x2f8f4a, { side: THREE.DoubleSide }));
  shade.position.y = -0.1;
  lamp.add(shade);
  const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.22, 6, 4), new THREE.MeshBasicMaterial({ color: 0xfff1b8 }));
  bulb.position.y = -0.4;
  lamp.add(bulb);
  room.add(lamp);
  api.bulb = bulb;

  return api;
}

function potPlant(scale, x, y, z) {
  const g = new VoxelGrid().box(-2, 0, -2, 2, 3, 2, 0xb8613a).box(-2, 3, -2, 2, 3, 2, 0x5a3a22);
  for (let i = 0; i < 26; i++) {
    const a = i * 2.4, r = 1 + (i % 4);
    g.set(Math.round(Math.cos(a) * r * 0.8), 4 + Math.floor(i / 4), Math.round(Math.sin(a) * r * 0.8), i % 3 ? 0x3f9a3a : 0x5cbf4a);
  }
  const m = g.build({ size: 0.1 * scale, material: mat(0xffffff) });
  m.position.set(x, y, z);
  return m;
}
