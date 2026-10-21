// Feed: the kitchen. Tap the leg bone to put it in the pan, hold to heat it
// until it's golden, then drag it to Rex (or tap him) and he eats it.
import * as THREE from 'three';
import { VoxelGrid } from '../voxel.js';
import { mat, lights } from '../minigames/common.js';
import { CareScene, buildRoom, box, legBone, CUBE } from './common.js';

const RAW = new THREE.Color(0xf2a0a0);
const COOKED = new THREE.Color(0xc8742c);
const BURNT = new THREE.Color(0x5a3a22);
const PAN = new THREE.Vector3(-0.5, 1.25, 0.6);
const HOVER = new THREE.Vector3(-0.35, 2.0, 0.7);
const HEAT_RATE = 0.36; // per second held: ~2.8s to just right

export class KitchenScene extends CareScene {
  constructor(ctx) {
    super(ctx);
    this.scene.background = new THREE.Color(0xfff1c9);
    lights(this.scene, { sky: 0xffffff, ground: 0x9a7a5a, hemi: 1.9, sun: 1.8 });
    this.heat = 0;
    this.build();
    this.frame(new THREE.Vector3(-0.2, 1.75, 0.2), new THREE.Vector3(0, 0.3, 1), [4.3, 4.4], [8.5, 6.2], new THREE.Vector3(-0.2, 2.0, 0.2));
  }

  build() {
    const sc = this.scene;
    buildRoom(sc, { floorA: 0xf4f1ea, floorB: 0x3b4a5a, wall: 0xfff1c9, trim: 0xe0b070 });
    // Backsplash tiles, window, cabinets, fridge.
    const tiles = new VoxelGrid();
    for (let x = -16; x < 16; x++) for (let y = 0; y < 3; y++) tiles.set(x, y, 0, (x + y) & 1 ? 0xd8eef7 : 0xffffff);
    const t = tiles.build({ size: 0.5, jitter: 0.02, material: mat(0xffffff), shadow: false });
    t.position.set(0.25, 1.25, -4.78);
    sc.add(t);
    box(sc, 2.4, 1.8, 0.1, 0xffffff, 2.8, 3.7, -4.76);
    box(sc, 2.1, 1.5, 0.1, 0x9fd8ff, 2.8, 3.7, -4.7);
    box(sc, 0.08, 1.5, 0.1, 0xffffff, 2.8, 3.7, -4.66);
    for (const x of [-3.6, -2.2, -0.8]) {
      box(sc, 1.3, 1.2, 0.6, 0xc98a55, x, 4.1, -4.5);
      box(sc, 0.1, 0.3, 0.05, 0x6b4a2a, x + 0.45, 3.8, -4.18);
    }
    box(sc, 1.6, 3.6, 1.2, 0xf4f6fa, -5.6, 1.8, -3.9);
    box(sc, 0.08, 0.9, 0.06, 0x94a3b8, -5, 2.6, -3.28);

    // Counter with the stove in it.
    box(sc, 6.4, 0.85, 1.4, 0x9a6440, 0, 0.425, 0.6);
    box(sc, 6.6, 0.12, 1.55, 0xece8e0, 0, 0.91, 0.6);
    for (const x of [-2.4, -0.8, 0.8, 2.4]) box(sc, 1.4, 0.6, 0.04, 0x86542f, x, 0.45, 1.31);
    box(sc, 1.3, 0.03, 1.0, 0x2b2f36, -0.5, 0.985, 0.6);
    for (const x of [-0.85, -0.15]) box(sc, 0.14, 0.14, 0.08, 0x1f2937, x, 0.72, 1.33);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.05, 4, 14), mat(0x555b66));
    ring.rotation.x = Math.PI / 2;
    ring.position.set(-0.5, 1.0, 0.6);
    sc.add(ring);
    this.flames = [];
    const flameMat = new THREE.MeshBasicMaterial({ color: 0xff8a1f });
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const f = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.18, 4), flameMat);
      f.position.set(-0.5 + Math.cos(a) * 0.3, 1.06, 0.6 + Math.sin(a) * 0.3);
      f.visible = false;
      sc.add(f);
      this.flames.push(f);
    }
    this.glow = new THREE.PointLight(0xff7a1a, 0, 3);
    this.glow.position.set(-0.5, 1.2, 0.8);
    sc.add(this.glow);
    const pan = new THREE.Mesh(new THREE.CylinderGeometry(0.44, 0.38, 0.1, 14), mat(0x3a3f47));
    pan.position.set(-0.5, 1.07, 0.6);
    pan.castShadow = true;
    sc.add(pan);
    const handle = box(sc, 0.7, 0.06, 0.12, 0x1f2937, 0.12, 1.1, 0.9);
    handle.rotation.y = 0.45;

    // Plate with the raw leg bone.
    const plate = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.42, 0.05, 16), mat(0xffffff));
    plate.position.set(-1.65, 1.0, 0.65);
    sc.add(plate);
    this.bone = legBone();
    this.bone.scale.setScalar(1.5);
    this.bone.position.set(-1.65, 1.2, 0.65);
    this.bone.rotation.y = 0.5;
    this.bone.userData.meat.color.copy(RAW);
    sc.add(this.bone);

    // Rex behind the counter, bib on.
    const { rex, group } = this.makeRex(0.95);
    group.position.set(0.95, 0, -0.35);
    this.rex = rex;
    this.rexGroup = group;
    const bib = new THREE.Group();
    box(bib, 0.62, 0.5, 0.04, 0xffffff, 0, 0, 0);
    box(bib, 0.66, 0.06, 0.05, 0xe5484d, 0, 0.25, 0);
    box(bib, 0.66, 0.06, 0.05, 0xe5484d, 0, -0.25, 0);
    box(bib, 0.14, 0.14, 0.05, 0xe5484d, 0, 0, 0.01);
    bib.position.set(0, 0.42, 0.6);
    rex.body.add(bib);
  }

  start() {
    this.state = 'pick';
    this.rex.play('happy', 1, this.idleMode());
    this.coach('Tap the leg bone to put it in the pan 🍖');
  }

  onDown(x, y) {
    if (this.state === 'pick') {
      if (this.near(x, y, this.bone, 110) || this.hit(x, y, this.bone)) this.toPan();
    } else if (this.state === 'heat') {
      this.hud.setCursor(null);
      this.sfx.tap();
    } else if (this.state === 'serve') {
      this.dragging = this.near(x, y, this.bone, 100) || !!this.hit(x, y, this.bone);
      if (!this.dragging && this.hit(x, y, this.rex.root)) this.eat();
    }
  }

  onDrag(x, y) {
    if (this.state !== 'serve' || !this.dragging) return;
    const p = this.planePointZ(x, y, 0.35);
    if (!p) return;
    p.y = Math.max(1.1, p.y);
    this.bone.position.copy(p);
    this.rex.lookAt(((x / innerWidth) * 2 - 1) * 0.8);
  }

  onUp(x, y, d) {
    if (this.state === 'heat') this.stopHeat();
    else if (this.state === 'serve' && this.dragging) {
      this.dragging = false;
      const close = this.near(x, y, this.mouth(this.rex), 130) || this.hit(x, y, this.rex.root);
      if (close || d.dist < 12) this.eat();
      else {
        const from = this.bone.position.clone();
        this.tween(0.3, (k) => this.bone.position.lerpVectors(from, HOVER, k));
      }
    }
  }

  toPan() {
    this.state = 'moving';
    this.sfx.tap();
    const from = this.bone.position.clone();
    const r0 = this.bone.rotation.y;
    this.tween(0.55, (k) => {
      this.bone.position.lerpVectors(from, PAN, k);
      this.bone.position.y += Math.sin(k * Math.PI) * 0.8;
      this.bone.rotation.y = r0 + (Math.PI * 2 - r0 + 0.2) * k;
    }, () => {
      this.sfx.sizzle();
      this.state = 'heat';
      this.coach('Press and hold to heat it up 🔥');
      this.updateHeatHud();
    });
  }

  heatLabel() {
    const h = this.heat;
    if (h < 0.05) return 'Raw';
    if (h < 0.85) return 'Warming up…';
    if (h <= 1.15) return 'Just right!';
    return 'Too hot!';
  }

  updateHeatHud() {
    this.hud.setStats(`<span>🌡️ ${this.heatLabel()}</span>`);
    this.hud.setProgress(Math.min(1, this.heat / 1.3));
  }

  stopHeat() {
    const h = this.heat;
    if (h < 0.85) {
      if (h > 0.03) this.coach('Keep going! Hold a little longer 🔥');
      return;
    }
    this.cooked(h <= 1.15 ? 'perfect' : 'crispy');
  }

  cooked(quality) {
    this.state = 'moving';
    this.quality = quality;
    this.sfx.ding();
    this.hud.setProgress(null);
    this.hud.setStats(`<span>${quality === 'perfect' ? '⭐ Perfect!' : '😅 A bit crispy'}</span>`);
    this.hud.say(quality === 'perfect' ? 'Perfect! ⭐' : 'A bit crispy!', 1100);
    const from = this.bone.position.clone();
    this.tween(0.45, (k) => {
      this.bone.position.lerpVectors(from, HOVER, k);
      this.bone.position.y += Math.sin(k * Math.PI) * 0.4;
    }, () => {
      this.state = 'serve';
      this.rex.play('happy', 1.2, this.idleMode());
      this.coach(quality === 'perfect' ? 'Yum! Drag the bone to Rex 😋' : "Rex doesn't mind! Drag it to him 😋");
    });
  }

  eat() {
    if (this.state !== 'serve') return;
    this.state = 'eating';
    this.coach('');
    this.hud.setStats('');
    const from = this.bone.position.clone();
    const to = this.mouth(this.rex);
    this.tween(0.3, (k) => this.bone.position.lerpVectors(from, to, k), () => {
      this.chewing = true;
      this.rex.play('eat', 2.4, 'happy');
      const before = this.game.state.needs.hunger;
      [0, 0.75, 1.5].forEach((at, i) => this.later(at, () => {
        this.sfx.chomp();
        this.bone.scale.setScalar(1.5 * (1 - (i + 1) / 3));
        this.burst(this.mouth(this.rex), 0xc8742c, 6, 2, 0.06);
      }));
      this.later(2.3, () => {
        this.chewing = false;
        this.bone.visible = false;
        const r = this.game.feed();
        const gain = Math.round(this.game.state.needs.hunger - before);
        this.sfx.happy();
        this.rex.play('cheer', 1.6, this.idleMode());
        this.hud.say('Yum! 😋', 1200);
        this.later(1.6, () => this.finish({
          icon: '🍖',
          title: 'Yum!',
          line: this.quality === 'perfect' ? 'Rex loved his leg bone. Cooked just right!' : 'Rex gobbled up his leg bone!',
          gain: r.ok ? `🍖 Food +${gain}` : '',
        }));
      });
    });
  }

  tick(dt, t) {
    const heating = this.state === 'heat' && !!this.down;
    for (const f of this.flames) {
      f.visible = heating;
      if (heating) f.scale.y = 0.8 + Math.sin(t * 30 + f.position.x * 20) * 0.35;
    }
    this.glow.intensity += ((heating ? 2.2 : 0) - this.glow.intensity) * Math.min(1, dt * 8);
    if (heating) {
      this.heat += dt * HEAT_RATE;
      this.sizzleT = (this.sizzleT || 0) - dt;
      if (this.sizzleT <= 0) {
        this.sizzleT = 0.22;
        this.sfx.sizzle();
        this.steam(PAN);
      }
      this.updateHeatHud();
      if (this.heat >= 1.3) this.cooked('crispy');
    }
    // Meat colour follows the heat.
    const meat = this.bone.userData.meat.color;
    if (this.heat <= 1) meat.copy(RAW).lerp(COOKED, Math.max(0, this.heat));
    else meat.copy(COOKED).lerp(BURNT, Math.min(1, (this.heat - 1) / 0.4));

    if (this.state === 'serve' && !this.dragging) {
      this.bone.position.y = HOVER.y + Math.sin(t * 3) * 0.06;
      this.bone.rotation.y += dt * 0.8;
      if (Math.random() < dt * 3) this.steam(this.bone.position);
    }
    if (this.chewing) this.bone.position.copy(this.mouth(this.rex));
    this.rex.update(dt, t);
  }

  steam(at) {
    const m = new THREE.Mesh(CUBE, mat(0xffffff, { transparent: true, opacity: 0.8 }));
    m.scale.setScalar(0.07 + Math.random() * 0.05);
    m.position.copy(at).add(new THREE.Vector3((Math.random() - 0.5) * 0.4, 0.1, (Math.random() - 0.5) * 0.3));
    this.spawn(m, { v: new THREE.Vector3((Math.random() - 0.5) * 0.3, 0.9, 0), gravity: -0.4, life: 1.1, spin: 2 });
  }
}
