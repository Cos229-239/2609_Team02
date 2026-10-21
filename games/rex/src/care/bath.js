// Wash: bath time. Five steps, each done by rubbing over Rex with a tool:
// hose him, scrub with soap (mud turns to foam), hose the foam off, brush
// his teeth, then dry him with a towel (he shakes off the last drops).
import * as THREE from 'three';
import { mat, lights } from '../minigames/common.js';
import { CareScene, buildRoom, box, CUBE } from './common.js';
import { VoxelGrid } from '../voxel.js';

const STEPS = [
  { id: 'rinse1', icon: '💦', label: 'Rinse', tool: '🚿', coach: 'Spray Rex with water! Rub over him 💦' },
  { id: 'soap', icon: '🧼', label: 'Soap', tool: '🧼', coach: 'Scrub-a-dub! Rub soap all over Rex 🧼' },
  { id: 'rinse2', icon: '💦', label: 'Rinse', tool: '🚿', coach: 'Rinse off all the bubbles! 💦' },
  { id: 'teeth', icon: '🪥', label: 'Teeth', tool: '🪥', coach: 'Say "Ahh!" Brush his teeth 🪥' },
  { id: 'dry', icon: '☀️', label: 'Dry', tool: 'towel', coach: 'Dry Rex off with the towel!' },
];
const SPHERE = new THREE.IcosahedronGeometry(0.5, 0);
const MUD = 0x7a5230;
const FOAM = 0xffffff;
const WATER = 0x6cc8ff;

export class BathScene extends CareScene {
  constructor(ctx) {
    super(ctx);
    this.scene.background = new THREE.Color(0xbfe6f5);
    lights(this.scene, { sky: 0xffffff, ground: 0x7aaac0, hemi: 1.9, sun: 1.7 });
    this.step = 0;
    this.progress = 0;
    this.mud = [];
    this.foam = [];
    this.fx = 0; // rub distance since the last effect
    this.build();
    this.frame(new THREE.Vector3(0, 1.9, 0), new THREE.Vector3(0, 0.45, 1), [3.7, 4.6], [7.5, 6.2], new THREE.Vector3(0, 2.1, 0));
  }

  build() {
    const sc = this.scene;
    buildRoom(sc, { floorA: 0xdff2ff, floorB: 0xffffff, wall: 0xbfe6f5, trim: 0x7fc6e0 });
    const tiles = new VoxelGrid();
    for (let x = -16; x < 16; x++) for (let y = 0; y < 5; y++) tiles.set(x, y, 0, (x + y) & 1 ? 0xa8dcef : 0xd4f0fa);
    const t = tiles.build({ size: 0.5, jitter: 0.02, material: mat(0xffffff), shadow: false });
    t.position.set(0.25, 0.75, -4.78);
    sc.add(t);
    // Shower head and pipe, towel rack, shelf.
    box(sc, 0.12, 1.6, 0.12, 0xb8c2cc, -1.2, 3.2, -4.68);
    box(sc, 0.6, 0.14, 0.5, 0xb8c2cc, -1.2, 4.0, -4.45);
    box(sc, 1.6, 0.08, 0.1, 0xb8c2cc, 3.2, 3.1, -4.66);
    box(sc, 1.2, 1.4, 0.12, 0xff9db5, 3.2, 2.45, -4.6);
    box(sc, 1.2, 0.12, 0.13, 0xffffff, 3.2, 2.1, -4.58);
    box(sc, 1.8, 0.1, 0.5, 0xffffff, -3.4, 2.7, -4.55);
    for (const [x, c] of [[-4, 0xff7ab0], [-3.5, 0x7b5cf0], [-3, 0x22b35e]]) box(sc, 0.28, 0.5, 0.28, c, x, 3.0, -4.55);

    // Tub.
    // Hollow tub so the water shows.
    for (const z of [-0.86, 0.86]) box(sc, 3.4, 1.0, 0.18, 0xffffff, 0, 0.55, z);
    for (const x of [-1.61, 1.61]) box(sc, 0.18, 1.0, 1.9, 0xffffff, x, 0.55, 0);
    box(sc, 3.4, 0.15, 1.9, 0xffffff, 0, 0.12, 0);
    for (const z of [-0.92, 0.92]) box(sc, 3.6, 0.14, 0.3, 0xf4f6fa, 0, 1.08, z);
    for (const x of [-1.68, 1.68]) box(sc, 0.3, 0.14, 2.1, 0xf4f6fa, x, 1.08, 0);
    for (const x of [-1.5, 1.5]) for (const z of [-0.8, 0.8]) box(sc, 0.22, 0.2, 0.22, 0xf2c84b, x, 0.08, z);
    this.water = box(sc, 3.05, 0.06, 1.55, WATER, 0, 0.88, 0);
    this.water.material = new THREE.MeshLambertMaterial({ color: WATER, transparent: true, opacity: 0.8 });
    this.water.castShadow = false;
    // Rubber duck on the rim.
    const duck = new VoxelGrid()
      .ellipsoid(0, 0, 0, 2.2, 1.6, 1.8, 0xffd23f)
      .ellipsoid(1, 2, 0, 1.2, 1.2, 1.2, 0xffd23f)
      .set(2, 2, 1, 0x141414).set(2, 2, -1, 0x141414)
      .box(2, 1, -0.5, 3, 1, 0.5, 0xff8a1f)
      .build({ size: 0.07, material: mat(0xffffff) });
    duck.position.set(1.35, 1.25, 0.75);
    duck.rotation.y = -1.9;
    sc.add(duck);
    this.duck = duck;

    const { rex, group } = this.makeRex(0.95);
    group.position.set(0, 0.25, -0.15);
    this.rex = rex;
    this.rexGroup = group;
  }

  // Mud spots stuck on Rex, wherever rays from the front hit him.
  splatMud() {
    this.rexGroup.updateWorldMatrix(true, true);
    const bb = new THREE.Box3().setFromObject(this.rex.root);
    const c = bb.getCenter(new THREE.Vector3());
    const rc = new THREE.Raycaster();
    let tries = 0;
    while (this.mud.length < 14 && tries++ < 120) {
      const dir = new THREE.Vector3((Math.random() - 0.5) * 2, (Math.random() - 0.3) * 1.2, 0.6 + Math.random()).normalize();
      const aim = new THREE.Vector3(c.x + (Math.random() - 0.5) * 0.9, c.y + (Math.random() - 0.2) * 1.2, c.z);
      rc.set(aim.clone().addScaledVector(dir, 4), dir.clone().negate());
      const hit = rc.intersectObject(this.rex.root, true)[0];
      if (!hit || hit.point.y < 1.2 || hit.point.y > 2.75) continue;
      if (this.rex.eyes.some((e) => e === hit.object.parent)) continue;
      const m = new THREE.Mesh(CUBE, mat(MUD));
      m.rotation.set(Math.random() * 3, Math.random() * 3, 0);
      this.stickOn(hit, m, 0.16 + Math.random() * 0.1);
      this.mud.push(m);
    }
  }

  start() {
    this.splatMud();
    this.state = 'play';
    this.rex.play('happy', 1, this.idleMode());
    this.hud.say('Bath time! 🛁', 1100);
    this.beginStep();
  }

  get cur() { return STEPS[this.step]; }

  beginStep() {
    const s = this.cur;
    this.progress = 0;
    this.hud.setTools(STEPS.map((x, i) => ({ icon: x.icon, label: x.label, state: i < this.step ? 'done' : i === this.step ? 'now' : 'todo' })));
    this.hud.setCursor(s.tool);
    this.hud.setProgress(0);
    this.coach(s.coach);
    this.foamTotal = this.foam.length;
    if (s.id === 'teeth') this.rex.setMode('brush');
    else this.rex.setMode(this.idleMode());
  }

  onDown(x, y) { this.rub(x, y, 20); }
  onDrag(x, y, step) { this.rub(x, y, step); }

  rub(x, y, step) {
    if (this.state !== 'play' || this.busy) return;
    const s = this.cur;
    let hit;
    if (s.id === 'teeth') {
      hit = this.near(x, y, this.mouth(this.rex), 120) ? { point: this.mouth(this.rex) } : null;
      if (!hit) {
        const h = this.hit(x, y, this.rex.root);
        if (h && (h.object.parent === this.rex.head || h.object.parent === this.rex.jaw)) hit = h;
      }
    } else hit = this.hit(x, y, this.rex.root);
    if (!hit) return;
    const need = Math.max(1300, Math.min(innerWidth, innerHeight) * 3);
    this.progress = Math.min(1, this.progress + step / need);
    this.fx += step;
    this.rubbingT = 0.35;
    if (s.id !== 'teeth' && this.rex.mode !== 'wash') this.rex.setMode('wash');
    if (this.fx >= 22) {
      this.fx = 0;
      this.effect(s.id, hit, x, y);
    }
    if (s.id === 'rinse2' && this.foamTotal) {
      // Rinsing is done when the bubbles are gone.
      this.progress = Math.max(this.progress * 0.5, 1 - this.foam.length / this.foamTotal);
    }
    this.hud.setProgress(this.progress);
    if (this.progress >= 1) this.completeStep();
  }

  effect(id, hit, x, y) {
    const p = hit.point;
    if (id === 'rinse1' || id === 'rinse2') {
      this.sfx.water();
      this.burst(p, WATER, 6, 2.2, 0.06, 0.6);
      this.wet = true;
      if (id === 'rinse2') this.washFoam(p, 0.42);
    } else if (id === 'soap') {
      this.sfx.scrub();
      if (hit.object && this.foam.length < 45) {
        const m = new THREE.Mesh(SPHERE, mat(FOAM));
        this.stickOn(hit, m, 0.26 + Math.random() * 0.14);
        this.foam.push(m);
      }
      // Mud under the soap turns into foam.
      for (const m of this.mud) {
        if (!m.visible) continue;
        if (m.getWorldPosition(new THREE.Vector3()).distanceTo(p) < 0.38) m.visible = false;
      }
      if (Math.random() < 0.5) this.bubble(p);
    } else if (id === 'teeth') {
      this.sfx.squeak();
      this.hud.floatText('✨', x + (Math.random() - 0.5) * 40, y - 20);
    } else if (id === 'dry') {
      this.sfx.scrub();
      if (Math.random() < 0.6) this.burst(p, WATER, 2, 1.6, 0.05, 0.5);
    }
  }

  washFoam(p, r) {
    const wp = new THREE.Vector3();
    this.foam = this.foam.filter((m) => {
      m.getWorldPosition(wp);
      if (wp.distanceTo(p) > r) return true;
      this.burst(wp.clone(), FOAM, 4, 1.8, 0.07, 0.5);
      m.parent.remove(m);
      return false;
    });
  }

  bubble(at) {
    const m = new THREE.Mesh(SPHERE, mat(0xe8f8ff, { transparent: true, opacity: 0.7 }));
    m.scale.setScalar(0.1 + Math.random() * 0.1);
    m.position.copy(at);
    this.spawn(m, { v: new THREE.Vector3((Math.random() - 0.5) * 0.6, 0.8 + Math.random() * 0.5, 0.3), gravity: -0.2, life: 1.6, spin: 1 });
  }

  completeStep() {
    const s = this.cur;
    this.busy = true;
    this.hud.setProgress(1);
    this.sfx.star();
    if (s.id === 'soap') for (const m of this.mud) m.visible = false;
    if (s.id === 'rinse2') {
      const wp = new THREE.Vector3();
      for (const m of this.foam) { m.getWorldPosition(wp); this.burst(wp.clone(), FOAM, 3, 1.5, 0.06, 0.4); m.parent.remove(m); }
      this.foam = [];
    }
    const cheer = { rinse1: 'Splish splash! 💦', soap: 'So bubbly! 🫧', rinse2: 'All rinsed! ✨', teeth: 'Sparkly teeth! ✨', dry: 'All dry! ☀️' }[s.id];
    this.hud.say(cheer, 1000);
    if (s.id === 'dry') { this.finishBath(); return; }
    if (s.id === 'teeth') this.rex.play('happy', 0.9, this.idleMode());
    this.later(0.9, () => {
      this.busy = false;
      this.step++;
      this.beginStep();
    });
  }

  finishBath() {
    this.state = 'end';
    this.wet = false;
    this.hud.setCursor(null);
    this.hud.setTools(STEPS.map((x) => ({ icon: x.icon, label: x.label, state: 'done' })));
    this.coach('');
    this.rex.play('shake', 1.3, 'happy');
    this.sfx.splash();
    const c = new THREE.Box3().setFromObject(this.rex.root).getCenter(new THREE.Vector3());
    this.burst(c, WATER, 24, 4.5, 0.07, 0.9);
    const before = this.game.state.needs.clean;
    this.later(1.4, () => {
      this.rex.play('cheer', 1.6, this.idleMode());
      this.sfx.revive();
      for (let i = 0; i < 6; i++) this.later(i * 0.12, () => this.burst(c.clone().add(new THREE.Vector3((Math.random() - 0.5) * 1.2, Math.random() * 1, 0.4)), 0xfff6b0, 3, 1.2, 0.06, 0.6));
    });
    this.later(3, () => {
      const r = this.game.wash();
      this.finish({
        icon: '🫧',
        title: 'Squeaky clean!',
        line: 'Rinsed, scrubbed, brushed and dried. Rex smells great!',
        gain: r.ok ? `🫧 Clean +${Math.round(this.game.state.needs.clean - before)}` : '',
      });
    });
  }

  tick(dt, t) {
    if (this.rubbingT > 0) {
      this.rubbingT -= dt;
      if (this.rubbingT <= 0 && this.state === 'play' && this.cur.id !== 'teeth') this.rex.setMode(this.idleMode());
    }
    // Drips while he's wet.
    if (this.wet && Math.random() < dt * 5) {
      const c = this.rexGroup.position;
      const m = new THREE.Mesh(CUBE, mat(WATER));
      m.scale.setScalar(0.05);
      m.position.set(c.x + (Math.random() - 0.5) * 1.1, 1.6 + Math.random() * 0.8, c.z + 0.3 + Math.random() * 0.3);
      this.spawn(m, { v: new THREE.Vector3(0, -0.5, 0), gravity: 6, life: 0.5 });
    }
    const target = this.step === 1 || this.step === 2 ? 0.96 : this.step >= 3 ? 0.93 : 0.88;
    this.water.position.y += (target - this.water.position.y) * Math.min(1, dt * 2);
    this.duck.position.y = 1.25 + Math.sin(t * 2) * 0.02;
    this.duck.rotation.z = Math.sin(t * 1.6) * 0.08;
    this.rex.update(dt, t);
  }
}
