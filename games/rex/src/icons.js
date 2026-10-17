// Store icons rendered from the same voxel models the room uses, so what a
// child buys looks exactly like what shows up. Rendered once, small, and
// shown pixelated to match the scene.
import * as THREE from 'three';
import { VoxelGrid, hash3 } from './voxel.js';

const SIZE = 72;

function voxelModel(build, size = 0.1) {
  const g = new VoxelGrid();
  build(g);
  return g.build({ size, material: new THREE.MeshLambertMaterial(), shadow: false });
}

// Consumables only exist as icons (and as things Rex eats/uses).
const MODELS = {
  treat: () => voxelModel((g) => {
    g.ellipsoid(0, 0, 0, 4.2, 3.2, 3.2, (x, y, z) => (y > 1 ? 0xd9773a : hash3(x, y, z) > 0.6 ? 0xa94e22 : 0xc2622c));
    g.box(4, -1, -1, 8, 0, 0, 0xf4ecd8);
    g.box(8, -2, -2, 9, 1, 1, 0xf4ecd8);
  }),
  soap: () => voxelModel((g) => {
    g.box(-5, 0, -3, 5, 3, 3, (x, y) => (y === 3 ? 0x8fe3c0 : 0x4fc79a));
    for (const [x, y, z, r] of [[-3, 5, 0, 1.6], [1, 6, 1, 2.2], [4, 5, -1, 1.2]]) g.ellipsoid(x, y, z, r, r, r, 0xeafaff);
  }),
  medicine: () => voxelModel((g) => {
    g.ellipsoid(0, 0, 0, 6, 2.6, 2.6, (x) => (x < 0 ? 0xe5484d : 0xf7d046));
    g.box(-4, 2, -1, -2, 2, 0, 0xff9a9a);
  }),
  background: () => voxelModel((g) => {
    const sky = [0x7a4a78, 0xa9617f, 0xff7a59, 0xffb36b, 0xffd38a];
    for (let y = 0; y <= 9; y++)
      for (let x = -7; x <= 7; x++) {
        const frame = Math.abs(x) === 7 || y === 0 || y === 9 || x === 0;
        const hill = y <= 2 + Math.round(Math.sin(x * 0.7) * 0.8);
        g.set(x, y, 0, frame ? 0x8b5a2b : hill ? 0x5c7a33 : sky[Math.min(4, 9 - y)]);
      }
    g.box(-5, 6, 1, -4, 7, 1, 0xfff1b0);
  }),
};

function fromScene(world, id) {
  const r = world.room;
  const src = {
    ball: r.ball,
    hat: world.rex.hat,
    plush: r.decor.plush,
    plant: r.decor.plant,
    glowEgg: r.decor.glowEgg,
    ptero: world.ptero,
  }[id];
  if (!src) return null;
  const obj = src.clone(true);
  obj.position.set(0, 0, 0);
  obj.rotation.set(0, 0, 0);
  obj.visible = true;
  obj.traverse((o) => { o.visible = true; });
  return obj;
}

export function renderIcons(world, ids) {
  const out = {};
  let renderer;
  try {
    const canvas = document.createElement('canvas');
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, preserveDrawingBuffer: true });
    renderer.setPixelRatio(1);
    renderer.setSize(SIZE, SIZE, false);
    renderer.setClearColor(0x000000, 0);
    const camera = new THREE.PerspectiveCamera(28, 1, 0.01, 100);
    const box = new THREE.Box3();
    const sphere = new THREE.Sphere();
    const dir = new THREE.Vector3(0.9, 0.75, 1.6).normalize();

    for (const id of ids) {
      const obj = MODELS[id]?.() || fromScene(world, id);
      if (!obj) continue;
      const scene = new THREE.Scene();
      scene.add(new THREE.HemisphereLight(0xffffff, 0x8a7a66, 2.2));
      const sun = new THREE.DirectionalLight(0xffffff, 1.8);
      sun.position.set(2, 4, 3);
      scene.add(sun);
      // Three-quarter front view with wings up, so it reads at icon size.
      if (id === 'ptero') {
        obj.rotation.set(0.35, 0.7, 0);
        // children: [body, left wing, right wing] (see buildPtero).
        obj.children.slice(1, 3).forEach((w, k) => (w.rotation.z = k ? 0.5 : -0.5));
      }
      scene.add(obj);
      box.setFromObject(obj).getBoundingSphere(sphere);
      const dist = (sphere.radius / Math.sin(THREE.MathUtils.degToRad(14))) * 1.02;
      camera.position.copy(sphere.center).addScaledVector(dir, dist);
      camera.lookAt(sphere.center);
      renderer.render(scene, camera);
      out[id] = canvas.toDataURL('image/png');
    }
  } catch (_) {
    // No icons is fine: the store falls back to emoji.
  } finally {
    renderer?.dispose();
    renderer?.forceContextLoss();
  }
  return out;
}
