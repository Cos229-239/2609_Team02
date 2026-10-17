// Dance Steps (memoryRun): Rex runs onto a disco floor and hops tile to tile
// to show the pattern; the child repeats it. Rules follow
// lib/features/minigames/games/memory_run/memory_run_logic.dart, and the demo
// takes at least `stepMs` per step (the server checks play time against it).
import * as THREE from 'three';
import { Rex } from '../rex.js';
import { VoxelGrid } from '../voxel.js';
import { rng, mat, box, fitCamera, pick, toScreen } from './common.js';

const TILE_COLORS = [0xe5484d, 0x2f7be6, 0x22b35e, 0xf7b928];
const TILE = 2.1, GAP = 0.18;

export class DanceGame {
  constructor({ settings, seed, hud, sfx, onFinish }) {
    this.s = settings; this.hud = hud; this.sfx = sfx; this.onFinish = onFinish;
    const r = rng(seed);
    this.sequence = Array.from({ length: settings.targetLength }, () => r.int(4));
    this.round = 1; this.inputIndex = 0; this.phase = 'intro';
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x1d1240);
    this.scene.fog = new THREE.Fog(0x1d1240, 14, 34);
    this.camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.1, 100);
    this.build();
    this.resize();
    hud.setTitle('memoryRun');
    this.updateHud();
  }

  tilePos(i) {
    const x = (i % 2 ? 1 : -1) * (TILE + GAP) / 2;
    const z = (i < 2 ? -1 : 1) * (TILE + GAP) / 2;
    return new THREE.Vector3(x, 0, z);
  }

  build() {
    const sc = this.scene;
    sc.add(new THREE.HemisphereLight(0xb39cf0, 0x2a1a4a, 1.4));
    const key = new THREE.DirectionalLight(0xffffff, 1.4);
    key.position.set(3, 10, 6);
    key.castShadow = true;
    key.shadow.mapSize.set(512, 512);
    sc.add(key);

    // Checker surround + stage edge.
    const g = new VoxelGrid();
    for (let x = -10; x < 10; x++) for (let z = -8; z < 8; z++) g.set(x, 0, z, (x + z) % 2 ? 0x2a2050 : 0x352a66);
    const floor = g.build({ size: 0.6, jitter: 0.05, material: mat(0xffffff), shadow: false });
    floor.position.y = -0.32;
    sc.add(floor);
    box(sc, TILE * 2 + 1.0, 0.25, TILE * 2 + 1.0, 0x8a7a50, 0, -0.02, 0);
    // Back wall with speakers.
    box(sc, 16, 8, 0.4, 0x2a1a5e, 0, 4, -6);
    for (const x of [-4.5, 4.5]) {
      box(sc, 1.6, 2.6, 1.2, 0x15151f, x, 1.3, -4.4);
      for (const y of [0.8, 1.9]) {
        const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, 0.1, 10), mat(0x444455));
        cone.rotation.x = Math.PI / 2;
        cone.position.set(x, y, -3.78);
        sc.add(cone);
      }
    }

    this.tiles = TILE_COLORS.map((c, i) => {
      const m = new THREE.Mesh(
        new THREE.BoxGeometry(TILE, 0.22, TILE),
        new THREE.MeshLambertMaterial({ color: c, emissive: c, emissiveIntensity: 0.12, flatShading: true }),
      );
      m.position.copy(this.tilePos(i)).setY(0.12);
      m.receiveShadow = true;
      m.userData.i = i;
      m.userData.glow = 0;
      sc.add(m);
      const light = new THREE.PointLight(c, 0, 5, 1.5);
      light.position.copy(this.tilePos(i)).setY(1.2);
      sc.add(light);
      m.userData.light = light;
      return m;
    });

    // Disco ball + sweeping spotlights.
    this.ball = new THREE.Mesh(new THREE.IcosahedronGeometry(0.6, 1), new THREE.MeshLambertMaterial({ color: 0xdfe6ff, emissive: 0x4a4a6a, flatShading: true }));
    this.ball.position.set(0, 5.2, -0.5);
    sc.add(this.ball);
    box(sc, 0.05, 2.4, 0.05, 0x888888, 0, 6.6, -0.5);
    this.spots = [0xff5ab0, 0x5ac8ff, 0xffe45a].map((c, i) => {
      const l = new THREE.PointLight(c, 7, 12, 1.2);
      l.userData.phase = i * 2.1;
      sc.add(l);
      return l;
    });

    this.rex = new Rex();
    this.rex.baseYaw = 0;
    this.rexGroup = new THREE.Group();
    this.rexGroup.add(this.rex.root);
    this.rexGroup.scale.setScalar(0.62);
    this.rexGroup.position.set(-8, 0.24, 0.2);
    this.rexGroup.rotation.y = Math.PI / 2;
    sc.add(this.rexGroup);
    this.rex.setMode('run');
    this.home = new THREE.Vector3(0, 0.24, 0.2);
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    const portrait = innerWidth < innerHeight;
    fitCamera(this.camera, new THREE.Vector3(0, 1.2, 0.4), new THREE.Vector3(0, portrait ? 1.0 : 0.85, 1), portrait ? 5.2 : 9.5, portrait ? 6.6 : 6.2);
  }

  start() { this.phase = 'enter'; }

  updateHud() {
    this.hud.setStats(`<span>🪩 Step ${Math.min(this.round, this.s.targetLength)}/${this.s.targetLength}</span>`);
    this.hud.setProgress((this.reached()) / this.s.targetLength);
  }

  reached() {
    if (this.phase === 'completed') return this.s.targetLength;
    if (this.phase === 'roundWon') return this.round;
    return this.round - 1;
  }

  light(i, ms) {
    const t = this.tiles[i];
    t.userData.glow = 1;
    t.userData.until = performance.now() + ms;
    this.sfx.note(i);
  }

  // Demo: Rex hops onto each tile in turn; each step lasts stepMs (+ a gap).
  demo() {
    this.phase = 'demo';
    this.hud.setExtra('');
    this.steps = this.sequence.slice(0, this.round);
    this.demoIndex = -1;
    this.demoClock = -0.5;
    this.updateHud();
  }

  pointer(x, y) {
    if (this.phase !== 'input') return;
    const hit = pick(this.camera, x, y, this.tiles);
    if (!hit) return;
    const i = hit.object.userData.i;
    this.light(i, 320);
    this.rexHop(i);
    if (this.sequence[this.inputIndex] !== i) {
      this.phase = 'failed';
      this.tiles[i].userData.wrong = 1;
      this.end();
      return;
    }
    this.inputIndex++;
    if (this.inputIndex < this.round) return;
    if (this.round === this.s.targetLength) {
      this.phase = 'completed';
      this.end();
      return;
    }
    this.phase = 'roundWon';
    this.updateHud();
    this.sfx.star();
    const p = toScreen(this.camera, this.rexGroup.position.clone().setY(2));
    this.hud.floatText('Nice moves!', p.x, p.y, 'good');
    setTimeout(() => {
      this.rex.play('cheer', 0.7, 'dance');
      setTimeout(() => {
        if (this.phase !== 'roundWon') return;
        this.round++;
        this.inputIndex = 0;
        this.demo();
      }, 900);
    }, 250);
  }

  replay() {
    if (this.phase !== 'input') return;
    this.inputIndex = 0;
    this.demo();
  }

  rexHop(i) {
    this.hopFrom = this.rexGroup.position.clone();
    this.hopTo = i < 0 ? this.home.clone() : this.tilePos(i).setY(0.24).add(new THREE.Vector3(0, 0, 0.15));
    this.hopT = 0;
    this.hopDur = Math.min(0.32, this.s.stepMs / 1000 * 0.45);
  }

  update(dt, t) {
    const g = this.rexGroup;
    if (this.phase === 'enter') {
      if (g.position.x < 0) {
        g.position.x = Math.min(0, g.position.x + dt * 8);
      } else {
        g.rotation.y += (0 - g.rotation.y) * Math.min(1, dt * 6);
        if (Math.abs(g.rotation.y) < 0.05) {
          this.rex.setMode('dance');
          this.startedAt = performance.now();
          this.hud.say('Watch Rex dance! 🪩', 1300);
          setTimeout(() => this.demo(), 900);
          this.phase = 'wait';
        }
      }
    } else if (this.phase === 'demo') {
      this.demoClock += dt;
      const stepS = this.s.stepMs / 1000 + 0.15;
      const k = Math.floor(this.demoClock / stepS);
      if (this.demoClock >= 0 && k !== this.demoIndex && k < this.steps.length) {
        this.demoIndex = k;
        this.rexHop(this.steps[k]);
        this.light(this.steps[k], this.s.stepMs);
      }
      if (this.demoClock >= this.steps.length * stepS + 0.1) {
        this.phase = 'input';
        this.inputIndex = 0;
        this.rexHop(-1);
        this.hud.say('Your turn!', 900);
        this.hud.setExtra('<button class="btn" data-game-act="replay">↺ Show me again</button>');
      }
    }

    // Hop arc (index -1 = back to the middle).
    if (this.hopT != null) {
      this.hopT += dt;
      const k = Math.min(1, this.hopT / this.hopDur);
      g.position.lerpVectors(this.hopFrom, this.hopTo, k);
      g.position.y = 0.24 + Math.sin(k * Math.PI) * 0.8;
      if (k >= 1) this.hopT = null;
    }

    const now = performance.now();
    for (const tile of this.tiles) {
      const u = tile.userData;
      if (u.glow && now > u.until) u.glow = Math.max(0, u.glow - dt * 6);
      const wrong = u.wrong ? 1 : 0;
      tile.material.emissiveIntensity = 0.12 + u.glow * 1.1;
      if (wrong) tile.material.emissive.setHex(0xffffff);
      tile.position.y = 0.12 - u.glow * 0.06;
      u.light.intensity = u.glow * 9;
    }
    this.ball.rotation.y += dt * 0.8;
    for (const l of this.spots) {
      const a = t * 0.9 + l.userData.phase;
      l.position.set(Math.cos(a) * 3, 3.2, Math.sin(a) * 2);
    }
    this.rex.update(dt, t);
  }

  end() {
    const won = this.phase === 'completed';
    this.hud.setExtra('');
    this.updateHud();
    setTimeout(() => {
      this.rex.setMode(won ? 'cheer' : 'sad');
      won ? this.sfx.win() : this.sfx.lose();
      this.hud.say(won ? 'Dance champion! 🏆' : 'Oops, wrong step!', 1400);
    }, 250);
    const elapsedMs = Math.round(performance.now() - this.startedAt);
    const details = { reached: this.reached(), target: this.s.targetLength };
    setTimeout(() => this.onFinish({ details, completed: won, elapsedMs }), 1800);
  }

  dispose() {}
}
