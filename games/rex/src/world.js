// three.js world: renderer (low-res + pixelated upscale), camera framing,
// lighting, and syncing Rex/room visuals to game state.
import * as THREE from 'three';
import { buildRoom } from './room.js';
import { Rex, buildFossil, buildPtero } from './rex.js';

const BED_TOP = 0.3;
const FOV = 38;

export class World {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.BasicShadowMap; // hard, pixel-y shadows
    this.renderer.setClearColor(0x1b2a55);

    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(0x1b2a55, 30, 60);
    this.camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 100);
    this.target = new THREE.Vector3(0, 2.3, 0);
    this.panelProgress = 0;
    this.pixel = 3;

    this.hemi = new THREE.HemisphereLight(0xcfe0ff, 0x6b4a2b, 1.8);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xfff0d6, 2.4);
    this.sun.position.set(-4, 11, 7);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(512, 512);
    Object.assign(this.sun.shadow.camera, { left: -9, right: 9, top: 9, bottom: -9, near: 1, far: 30 });
    this.sun.shadow.bias = -0.002;
    this.scene.add(this.sun);
    this.lamp = new THREE.PointLight(0xffd59a, 22, 14, 1.5);
    this.lamp.position.set(0, 8.2, 0.5);
    this.scene.add(this.lamp);

    this.room = buildRoom();
    this.scene.add(this.room.group);

    this.rex = new Rex();
    this.rex.root.position.y = BED_TOP;
    this.rexHolder = new THREE.Group();
    this.rexHolder.add(this.rex.root);
    this.scene.add(this.rexHolder);

    this.fossil = buildFossil();
    this.fossil.position.set(0, BED_TOP + 0.2, 0.3);
    this.fossil.rotation.x = 0.35; // tip the bones toward the camera
    this.fossil.scale.setScalar(1.15);
    this.fossil.visible = false;
    this.scene.add(this.fossil);

    this.ptero = buildPtero();
    this.ptero.visible = false;
    this.scene.add(this.ptero);

    this.raycaster = new THREE.Raycaster();
    this.ndc = new THREE.Vector2();
    this.tmp = new THREE.Vector3();
    this.night = 0; // 0..1 blend
    this.nightTarget = 0;
    this.fossilBlend = 0;
    this.ballAnim = null;
    this.foodTimer = 0;
    this.theme = 'day';
    this.resize();
  }

  setPixel(px) {
    this.pixel = px;
    this.resize();
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    // Pixel setting is in device pixels so phones (3x) and laptops (2x) match:
    // 1 = full res, 2 = crisp pixel art, 3 = chunky.
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    const factor = { 1: 1, 2: 3, 3: 5 }[this.pixel] || 3;
    this.renderer.setPixelRatio(Math.min(dpr, Math.max(0.2, dpr / factor)));
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    // Keep the bed + Rex framed on any screen shape.
    const tan = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
    const wide = w >= 1100 && h >= 560;
    const W = wide ? 9 : 4.9, H = 7;
    this.dist = Math.min(26, Math.max(W / (2 * tan * this.camera.aspect), H / (2 * tan)));
  }

  setPanelProgress(p) {
    this.panelProgress = p;
  }

  // Syncs visuals that follow persistent state (owned items, night, etc).
  applyState(s) {
    const o = s.owned;
    this.rex.hat.visible = !!o.hat;
    this.room.ball.visible = !!o.ball;
    this.room.decor.plant.visible = !!o.plant;
    this.room.decor.plush.visible = !!o.plush;
    this.room.decor.glowEgg.visible = !!o.glowEgg;
    this.ptero.visible = !!o.ptero && s.status !== 'fossil';
    this.nightTarget = s.sleeping ? 1 : 0;
    const theme = s.sleeping ? 'night' : o.background ? 'sunset' : 'day';
    if (theme !== this.theme) {
      this.theme = theme;
      this.room.setWindowTheme(theme);
    }
    const fossil = s.status === 'fossil';
    this.rex.root.visible = !fossil;
    this.fossil.visible = fossil;
    if (!this.rex.actionUntil) {
      this.rex.setMode(fossil ? 'idle' : s.sleeping ? 'sleep' : s.status === 'sick' ? 'sick' : 'idle');
    }
  }

  playBall() {
    this.ballAnim = { t: 0 };
  }

  showFood() {
    this.room.food.visible = true;
    this.foodTimer = 4;
  }

  shakeFossil() {
    this.fossilShake = 0.6;
  }

  pick(clientX, clientY) {
    this.ndc.set((clientX / window.innerWidth) * 2 - 1, -(clientY / window.innerHeight) * 2 + 1);
    this.raycaster.setFromCamera(this.ndc, this.camera);
    const targets = [
      ['rex', this.rex.root],
      ['fossil', this.fossil],
      ['ball', this.room.ball],
      ['bowl', this.room.bowl],
    ].filter(([, o]) => o.visible);
    let best = null;
    for (const [name, obj] of targets) {
      const hit = this.raycaster.intersectObject(obj, true)[0];
      if (hit && (!best || hit.distance < best.d)) best = { name, d: hit.distance };
    }
    return best?.name || null;
  }

  // Screen (CSS px) position of a 3D object, for HTML bubbles/particles.
  screenPos(obj) {
    obj.getWorldPosition(this.tmp);
    this.tmp.project(this.camera);
    return { x: (this.tmp.x + 1) / 2 * window.innerWidth, y: (1 - this.tmp.y) / 2 * window.innerHeight };
  }

  rexHeadScreen() {
    return this.screenPos(this.fossil.visible ? this.fossil : this.rex.anchor);
  }

  update(dt, t) {
    // Camera: slow idle drift + parallax toward the open panel.
    const px = this.panelProgress;
    const sway = Math.sin(t * 0.25) * 0.25;
    const dir = new THREE.Vector3(px * 0.35 + sway * 0.05, 0.24, 1).normalize();
    const pos = this.tmp.copy(this.target).addScaledVector(dir, this.dist);
    pos.x += px * 1.8;
    if (!this.cameraPlaced) { this.camera.position.copy(pos); this.cameraPlaced = true; }
    this.camera.position.lerp(pos, Math.min(1, dt * 6));
    this.camera.lookAt(this.target.x + px * 1.2, this.target.y, this.target.z);

    // Day/night lighting.
    this.night += (this.nightTarget - this.night) * Math.min(1, dt * 2);
    const n = this.night;
    this.hemi.intensity = 1.8 - n * 1.25;
    this.sun.intensity = 2.4 - n * 2.1;
    this.lamp.intensity = 22 - n * 16;
    this.room.bulb.material.color.setHex(n > 0.5 ? 0x8a7a50 : 0xfff1b8);

    // Fossil mode drains colour from the room a little.
    this.fossilBlend += ((this.fossil.visible ? 1 : 0) - this.fossilBlend) * Math.min(1, dt * 2);
    this.hemi.color.setRGB(0.81 - this.fossilBlend * 0.15, 0.88 - this.fossilBlend * 0.2, 1 - this.fossilBlend * 0.3);
    if (this.fossilShake > 0) {
      this.fossilShake -= dt;
      this.fossil.position.x = Math.sin(t * 60) * 0.06 * this.fossilShake;
    } else this.fossil.position.x = 0;

    this.rex.update(dt, t);

    if (this.room.decor.glowEgg.visible) {
      const e = this.room.decor.glowEgg;
      const k = 0.6 + Math.sin(t * 2) * 0.3 + n * 0.6;
      e.userData.light.intensity = 2.5 * k;
      e.userData.mesh.material.emissiveIntensity = 0.5 + k * 0.5;
    }

    if (this.ptero.visible) {
      const a = t * 0.6;
      this.ptero.position.set(Math.cos(a) * 4.2, 6 + Math.sin(t * 1.3) * 0.4, Math.sin(a) * 2.2 - 1);
      this.ptero.rotation.y = -a;
      const flap = Math.sin(t * 9) * 0.6;
      this.ptero.userData.wings[0].rotation.z = -flap;
      this.ptero.userData.wings[1].rotation.z = flap;
    }

    if (this.ballAnim) {
      const b = this.ballAnim;
      b.t += dt;
      const k = b.t / 2.4;
      const ball = this.room.ball;
      if (k >= 1) {
        ball.position.copy(this.room.ballHome);
        this.ballAnim = null;
      } else {
        const x = THREE.MathUtils.lerp(this.room.ballHome.x, 0.4, Math.sin(k * Math.PI));
        const z = THREE.MathUtils.lerp(this.room.ballHome.z, 1.8, Math.sin(k * Math.PI));
        ball.position.set(x, 0.42 + Math.abs(Math.sin(k * Math.PI * 5)) * 1.6, z);
        ball.rotation.x += dt * 8;
      }
    }

    if (this.foodTimer > 0) {
      this.foodTimer -= dt;
      if (this.foodTimer <= 0) this.room.food.visible = false;
    }

    this.renderer.render(this.scene, this.camera);
  }
}
