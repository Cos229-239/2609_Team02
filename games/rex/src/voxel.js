// Tiny voxel toolkit: fill a sparse grid with shapes, then turn it into a
// single InstancedMesh of cubes (hidden interior voxels are skipped).
import * as THREE from 'three';

const BOX = new THREE.BoxGeometry(1, 1, 1);

// Deterministic 0..1 noise per voxel so colour jitter is stable across builds.
export function hash3(x, y, z) {
  let h = (x * 374761393 + y * 668265263 + z * 1442695041) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

export class VoxelGrid {
  constructor() {
    this.map = new Map();
  }

  key(x, y, z) {
    return x + ',' + y + ',' + z;
  }

  set(x, y, z, c) {
    this.map.set(this.key(x, y, z), { x, y, z, c });
    return this;
  }

  del(x, y, z) {
    this.map.delete(this.key(x, y, z));
  }

  has(x, y, z) {
    return this.map.has(this.key(x, y, z));
  }

  // color: hex number, or fn(x, y, z, nx, ny, nz) where n* are the -1..1
  // normalised offsets inside the ellipsoid (useful for bellies/shading).
  ellipsoid(cx, cy, cz, rx, ry, rz, color) {
    for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++)
      for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
        for (let z = Math.floor(cz - rz); z <= Math.ceil(cz + rz); z++) {
          const nx = (x - cx) / rx, ny = (y - cy) / ry, nz = (z - cz) / rz;
          if (nx * nx + ny * ny + nz * nz <= 1) {
            const c = typeof color === 'function' ? color(x, y, z, nx, ny, nz) : color;
            if (c != null) this.set(x, y, z, c);
          }
        }
    return this;
  }

  // Inclusive box.
  box(x0, y0, z0, x1, y1, z1, color) {
    for (let x = x0; x <= x1; x++)
      for (let y = y0; y <= y1; y++)
        for (let z = z0; z <= z1; z++) {
          const c = typeof color === 'function' ? color(x, y, z) : color;
          if (c != null) this.set(x, y, z, c);
        }
    return this;
  }

  recolor(fn) {
    for (const v of this.map.values()) {
      const c = fn(v);
      if (c != null) v.c = c;
    }
    return this;
  }

  build({ size = 0.1, jitter = 0.06, material, origin = [0, 0, 0], shadow = true } = {}) {
    const list = [];
    for (const v of this.map.values()) {
      const hidden =
        this.has(v.x + 1, v.y, v.z) && this.has(v.x - 1, v.y, v.z) &&
        this.has(v.x, v.y + 1, v.z) && this.has(v.x, v.y - 1, v.z) &&
        this.has(v.x, v.y, v.z + 1) && this.has(v.x, v.y, v.z - 1);
      if (!hidden) list.push(v);
    }
    const mat = material || new THREE.MeshLambertMaterial();
    const mesh = new THREE.InstancedMesh(BOX, mat, Math.max(1, list.length));
    mesh.count = list.length;
    const m = new THREE.Matrix4();
    const col = new THREE.Color();
    list.forEach((v, i) => {
      m.makeScale(size, size, size);
      m.setPosition((v.x - origin[0]) * size, (v.y - origin[1]) * size, (v.z - origin[2]) * size);
      mesh.setMatrixAt(i, m);
      col.set(v.c);
      if (jitter) col.offsetHSL(0, 0, (hash3(v.x, v.y, v.z) - 0.5) * jitter);
      mesh.setColorAt(i, col);
    });
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = shadow;
    mesh.receiveShadow = true;
    mesh.frustumCulled = false;
    // Kept so repaint() can recolour the mesh later without rebuilding it.
    mesh.userData.voxels = list;
    mesh.userData.jitter = jitter;
    return mesh;
  }
}

// Recolours a mesh made by VoxelGrid.build: fn(originalColor) → new colour.
// Always maps from the colours the grid was built with, so it can be re-run.
export function repaint(mesh, fn) {
  const { voxels, jitter } = mesh.userData;
  if (!voxels || !mesh.isInstancedMesh) return;
  const col = new THREE.Color();
  voxels.forEach((v, i) => {
    col.set(fn(v.c));
    if (jitter) col.offsetHSL(0, 0, (hash3(v.x, v.y, v.z) - 0.5) * jitter);
    mesh.setColorAt(i, col);
  });
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
}

// Builds `grid` as a child group whose origin sits at `pivot` (voxel coords),
// positioned relative to the parent's pivot so it can rotate around its joint.
export function jointPart(grid, pivot, parentPivot, size, material) {
  const g = new THREE.Group();
  g.position.set(
    (pivot[0] - parentPivot[0]) * size,
    (pivot[1] - parentPivot[1]) * size,
    (pivot[2] - parentPivot[2]) * size,
  );
  g.add(grid.build({ size, material, origin: pivot }));
  return g;
}
