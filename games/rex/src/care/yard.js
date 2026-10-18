// Play: fetch in the backyard. Swipe up to throw the ball (or tap a spot on
// the grass); Rex runs after it, brings it back and drops it. Three fetches.
import * as THREE from 'three';
import { VoxelGrid, hash3 } from '../voxel.js';
import { mat, lights, voxelTree, skyBackdrop } from '../minigames/common.js';
import { CareScene, box, ballMesh, flowerDots } from './common.js';

const FETCHES = 3;
const REST = new THREE.Vector3(-0.35, 0.95, 4.8); // ball "in hand"
const DROP = new THREE.Vector3(-0.1, 0.22, 4.1); // where Rex drops it
const HOME = new THREE.Vector3(0.8, 0, 2.6);
const RUN_SPEED = 6.5;

export class YardScene extends CareScene {
  constructor(ctx) {
    super(ctx);
    this.scene.background = new THREE.Color(0x8fd0ff);
    this.scene.fog = new THREE.Fog(0x8fd0ff, 24, 55);
    this.camera.fov = 50;
    lights(this.scene);
    this.count = 0;
    this.build();
    this.resize();
  }

  resize() {
    this.camera.aspect = innerWidth / innerHeight;
    // Narrow screens: step back so Rex and the ball both fit.
    const back = innerWidth < innerHeight ? 2.2 : 0;
    this.camera.position.set(0, 3.1 + back * 0.3, 8.5 + back);
    this.camera.lookAt(0, 0.4, -3);
    this.camera.updateProjectionMatrix();
  }

  build() {
    const sc = this.scene;
    const g = new VoxelGrid();
    for (let x = -22; x < 22; x++) for (let z = -26; z < 12; z++) {
      const h = hash3(x, z, 4);
      g.set(x, 0, z, h > 0.6 ? 0x63c94a : h > 0.25 ? 0x56b840 : 0x4ca83a);
    }
    const ground = g.build({ size: 1, jitter: 0.04, material: mat(0xffffff), shadow: false });
    ground.position.y = -0.5;
    sc.add(ground);
    const back = skyBackdrop(140, 44);
    back.position.set(0, 14, -42);
    sc.add(back);
    // Fence.
    for (let x = -18; x <= 18; x += 1.2) box(sc, 0.22, 1.3, 0.16, 0xf5f0e6, x, 0.65, -15);
    for (const y of [0.45, 1.0]) box(sc, 37, 0.14, 0.1, 0xf5f0e6, 0, y, -15.05);
    for (let i = 0; i < 10; i++) {
      const t = voxelTree(1.4 + (i % 3) * 0.3, i + 3);
      t.position.set(-18 + i * 4 + (i % 2), 0, -18 - (i % 3) * 1.5);
      sc.add(t);
    }
    // Rex's doghouse.
    const house = new THREE.Group();
    box(house, 2, 1.4, 1.8, 0xf2c84b, 0, 0.7, 0);
    box(house, 0.8, 0.9, 0.05, 0x5a3a22, 0, 0.5, 0.91);
    const roofL = box(house, 1.3, 0.14, 2.1, 0xe5484d, -0.5, 1.75, 0);
    roofL.rotation.z = 0.7;
    const roofR = box(house, 1.3, 0.14, 2.1, 0xe5484d, 0.5, 1.75, 0);
    roofR.rotation.z = -0.7;
    house.position.set(-5.5, 0, -4);
    house.rotation.y = 0.5;
    sc.add(house);
    flowerDots(sc, { w: 24, z0: 6, d: 20 }, 60);

    this.ball = ballMesh(0.22);
    this.ball.position.copy(REST);
    sc.add(this.ball);
    this.shadow = new THREE.Mesh(new THREE.CircleGeometry(0.22, 12), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.25 }));
    this.shadow.rotation.x = -Math.PI / 2;
    sc.add(this.shadow);

    const { rex, group } = this.makeRex(0.55);
    group.position.copy(HOME);
    this.rex = rex;
    this.rexGroup = group;
  }

  start() {
    this.state = 'ready';
    this.rex.play('happy', 1.2, 'idle');
    this.coach('Swipe up to throw the ball! ⚽');
    this.updateHud();
  }

  updateHud() {
    this.hud.setStats(`<span>⚽ ${this.count}/${FETCHES}</span>`);
  }

  onUp(x, y, d) {
    if (this.state !== 'ready') return;
    const dx = x - d.sx, dy = y - d.sy;
    let target;
    let power;
    if (d.dist < 15) {
      // A tap: throw to that spot on the grass.
      const p = this.groundPoint(x, y, 0);
      if (!p) return;
      target = p;
      power = THREE.MathUtils.clamp((REST.z - p.z) / 13, 0.2, 1);
    } else {
      if (dy > -20) { this.coach('Swipe UP to throw! ☝️'); return; }
      power = THREE.MathUtils.clamp(-dy / (innerHeight * 0.45), 0.2, 1);
      const z = 1.5 - power * 13.5;
      const dist = REST.z - z;
      target = new THREE.Vector3(REST.x + (dx / -dy) * dist * 0.8, 0, z);
    }
    target.x = THREE.MathUtils.clamp(target.x, -7, 7);
    target.z = THREE.MathUtils.clamp(target.z, -12, 1.5);
    this.throwTo(target, power);
  }

  throwTo(target, power) {
    this.state = 'flying';
    this.coach(power > 0.75 ? 'Wow, a big throw! 💪' : 'Go get it, Rex!');
    this.sfx.throw();
    const from = this.ball.position.clone();
    const dist = from.distanceTo(target);
    const peak = 1.2 + dist * 0.18;
    const dir = target.clone().sub(from).setY(0).normalize();
    const land = target.clone().setY(0.22);
    this.ball.userData.spin = 10;
    this.tween(0.45 + dist * 0.05, (k) => {
      this.ball.position.lerpVectors(from, land, k);
      this.ball.position.y += 4 * peak * k * (1 - k);
    }, () => this.bounce(land, dir, power));
    // Rex takes off after it.
    this.later(0.25, () => { this.runTarget = this.ball; this.rexState = 'chase'; });
  }

  bounce(at, dir, power) {
    this.sfx.bounce();
    const hops = [[0.5, 0.35, 1.2 * power + 0.3], [0.18, 0.22, 0.5 * power + 0.15]];
    let pos = at.clone();
    const next = (i) => {
      if (i >= hops.length) { this.ball.userData.spin = 0; this.landed = true; return; }
      const [h, sec, len] = hops[i];
      const from = pos.clone();
      const to = pos.clone().addScaledVector(dir, len);
      to.x = THREE.MathUtils.clamp(to.x, -8, 8);
      to.z = Math.max(-13.5, to.z);
      pos = to;
      this.tween(sec, (k) => {
        this.ball.position.lerpVectors(from, to, k);
        this.ball.position.y = 0.22 + 4 * h * k * (1 - k);
      }, () => { if (i === 0) this.sfx.bounce(); next(i + 1); });
    };
    this.landed = false;
    next(0);
  }

  // Moves Rex toward `goal`; returns true on arrival.
  runToward(goal, dt) {
    const g = this.rexGroup;
    const to = new THREE.Vector3(goal.x - g.position.x, 0, goal.z - g.position.z);
    const d = to.length();
    if (d < 0.45) return true;
    const heading = Math.atan2(to.x, to.z);
    let diff = heading - g.rotation.y;
    diff = Math.atan2(Math.sin(diff), Math.cos(diff));
    g.rotation.y += diff * Math.min(1, dt * 10);
    g.position.addScaledVector(to.normalize(), Math.min(d, RUN_SPEED * dt));
    this.rex.setMode('run');
    return false;
  }

  tick(dt, t) {
    const g = this.rexGroup;
    if (this.rexState === 'chase') {
      const at = this.runToward(this.ball.position, dt);
      if (at && this.landed) {
        this.rexState = 'return';
        this.carrying = true;
        this.sfx.tap();
        this.coach('Rex got it! 🦖');
      } else if (at) this.rex.setMode('idle');
    } else if (this.rexState === 'return') {
      if (this.runToward(HOME, dt)) {
        this.rexState = 'turn';
      }
    } else if (this.rexState === 'turn') {
      let diff = Math.atan2(Math.sin(-g.rotation.y), Math.cos(-g.rotation.y));
      g.rotation.y += diff * Math.min(1, dt * 8);
      this.rex.setMode('idle');
      if (Math.abs(diff) < 0.08) this.drop();
    }
    if (this.carrying) this.ball.position.copy(this.mouth(this.rex)).add(new THREE.Vector3(0, -0.06, 0));
    if (this.ball.userData.spin) this.ball.rotation.x += this.ball.userData.spin * dt;
    if (this.state === 'ready') this.ball.position.y = REST.y + Math.sin(t * 2.5) * 0.04;
    this.shadow.position.set(this.ball.position.x, 0.02, this.ball.position.z);
    this.shadow.material.opacity = Math.max(0.05, 0.3 - this.ball.position.y * 0.06);
    this.rex.update(dt, t);
  }

  drop() {
    this.rexState = null;
    this.carrying = false;
    this.count++;
    this.updateHud();
    this.sfx.happy();
    this.rex.play('happy', 1.2, 'idle');
    this.hud.floatText('+⚽', innerWidth / 2, innerHeight * 0.45, 'good');
    const from = this.ball.position.clone();
    this.tween(0.3, (k) => {
      this.ball.position.lerpVectors(from, DROP, k);
      this.ball.position.y = from.y + (DROP.y - from.y) * k;
    }, () => {
      this.sfx.bounce();
      if (this.count >= FETCHES) { this.done(); return; }
      this.later(0.5, () => {
        const f = this.ball.position.clone();
        this.tween(0.35, (k) => this.ball.position.lerpVectors(f, REST, k), () => {
          this.state = 'ready';
          this.coach(this.count === FETCHES - 1 ? 'One more throw! ⚽' : 'Good boy! Throw again! ⚽');
        });
      });
    });
  }

  done() {
    this.state = 'end';
    this.coach('');
    const before = { ...this.game.state.needs };
    this.rex.play('cheer', 1.8, 'idle');
    this.sfx.win();
    this.hud.say('So fun! 🎉', 1300);
    this.later(1.8, () => {
      const r = this.game.playBall();
      const n = this.game.state.needs;
      this.finish({
        icon: '⚽',
        title: 'So fun!',
        line: `Rex fetched the ball ${FETCHES} times.`,
        gain: r.ok ? `⚽ Fun +${Math.round(n.fun - before.fun)} · ⚡ Energy ${Math.round(n.energy - before.energy)}` : '',
      });
    });
  }
}
