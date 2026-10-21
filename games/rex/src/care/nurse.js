// Medicine: the nurse's office. Nurse Penny explains that Rex gets sick when
// tasks aren't done, checks him with her stethoscope, then:
//  - healthy → says so;
//  - needs medicine but none in the bag → explains how to get some;
//  - needs medicine and has some → asks if she may treat him.
import * as THREE from 'three';
import { mat, lights } from '../minigames/common.js';
import { STORE_ITEMS } from '../data.js';
import { CareScene, buildRoom, box, buildNurse } from './common.js';

const NURSE = { who: '👩‍⚕️', name: 'Nurse Penny' };
const NURSE_HOME = new THREE.Vector3(-1.05, 0, 0.35);
const NURSE_AT_REX = new THREE.Vector3(-0.15, 0, 0.45);

export class NurseScene extends CareScene {
  constructor(ctx) {
    super(ctx);
    this.scene.background = new THREE.Color(0xd6f3ea);
    lights(this.scene, { sky: 0xffffff, ground: 0x8aa8a0, hemi: 1.9, sun: 1.6 });
    this.build();
    this.frame(new THREE.Vector3(0, 1.75, 0), new THREE.Vector3(0, 0.25, 1), [4.8, 5.8], [8.5, 7], new THREE.Vector3(0, 0.75, 0));
  }

  build() {
    const sc = this.scene;
    buildRoom(sc, { floorA: 0xf1f5f9, floorB: 0xdbe7ee, wall: 0xd6f3ea, trim: 0x8fd8c4 });
    // Medicine cabinet with a red cross.
    box(sc, 1.6, 1.6, 0.4, 0xffffff, -3, 3, -4.6);
    box(sc, 0.9, 0.24, 0.05, 0xe5484d, -3, 3, -4.38);
    box(sc, 0.24, 0.9, 0.05, 0xe5484d, -3, 3, -4.38);
    // Heart poster and height chart.
    box(sc, 1.4, 1.6, 0.06, 0xffffff, 2.6, 3.3, -4.76);
    for (const [x, y] of [[-0.2, 0.15], [0.2, 0.15], [0, -0.15], [-0.3, 0.3], [0.3, 0.3], [-0.1, 0], [0.1, 0]]) box(sc, 0.3, 0.3, 0.05, 0xe5484d, 2.6 + x, 3.3 + y, -4.71);
    box(sc, 0.5, 3, 0.05, 0xfff4cc, 4.4, 1.6, -4.76);
    for (let i = 0; i < 6; i++) box(sc, 0.25, 0.04, 0.06, 0xf08a24, 4.3, 0.5 + i * 0.5, -4.72);
    // Exam table.
    const tx = 1.0;
    box(sc, 2.3, 0.26, 1.2, 0x7fc6e0, tx, 0.95, 0);
    box(sc, 2.3, 0.03, 0.6, 0xffffff, tx, 1.095, 0);
    box(sc, 2.1, 0.1, 1.0, 0xb8c2cc, tx, 0.78, 0);
    for (const x of [-0.9, 0.9]) for (const z of [-0.4, 0.4]) box(sc, 0.1, 0.75, 0.1, 0x94a3b8, tx + x, 0.38, z);
    // Little stool + jar of lollipops.
    box(sc, 0.5, 0.06, 0.5, 0xffffff, 3.2, 1.0, -1.0);
    box(sc, 0.08, 1.0, 0.08, 0x94a3b8, 3.2, 0.5, -1.0);
    const jar = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.36, 10), mat(0xe8f8ff, { transparent: true, opacity: 0.6 }));
    jar.position.set(3.2, 1.21, -1.0);
    sc.add(jar);
    for (const [c, x] of [[0xff7ab0, -0.07], [0xffd23f, 0.07], [0x7b5cf0, 0]]) box(sc, 0.1, 0.1, 0.1, c, 3.2 + x, 1.45, -1.0);

    const { rex, group } = this.makeRex(0.6);
    group.position.set(tx + 0.1, 1.1, -0.05);
    group.rotation.y = -0.35;
    this.rex = rex;
    this.rexGroup = group;
    this.rex.setMode(this.sick ? 'sick' : 'sit');

    this.nurse = buildNurse();
    this.nurse.position.copy(NURSE_HOME);
    this.nurse.rotation.y = 0.5;
    sc.add(this.nurse);
  }

  rexMode() { return this.sick ? 'sick' : 'sit'; }

  say(text, buttons) {
    this.talkT = Math.min(3, 0.6 + text.length * 0.035);
    this.hud.setDialog({ ...NURSE, text, buttons });
  }

  start() {
    this.state = 'talk';
    this.stage = 'intro1';
    this.say("Hi there! I'm Nurse Penny 👋 I help dinos like Rex stay healthy.", [{ label: 'Next ▶', act: 'care-next', kind: 'green' }]);
  }

  act(name) {
    if (this.busy) return;
    if (name === 'next' && this.stage === 'intro1') {
      this.stage = 'intro2';
      this.say("Here's a secret: Rex can get sick when tasks don't get done. Doing your tasks keeps him fed, clean and happy! 📋",
        [{ label: 'Next ▶', act: 'care-next', kind: 'green' }]);
    } else if (name === 'next' && this.stage === 'intro2') {
      this.checkUp();
    } else if (name === 'yes' && this.stage === 'ask') {
      this.treat();
    } else if (name === 'no' && this.stage === 'ask') {
      this.stage = 'end';
      this.say('Okay! Come back anytime if Rex needs me 💚', [{ label: 'Back to Rex', act: 'back', kind: 'green' }]);
    }
  }

  walk(to, sec, done) {
    const from = this.nurse.position.clone();
    this.walking = true;
    this.tween(sec, (k) => this.nurse.position.lerpVectors(from, to, k), () => { this.walking = false; done?.(); });
  }

  checkUp() {
    this.stage = 'check';
    this.busy = true;
    this.say('Let me give Rex a quick check-up… 🩺');
    this.walk(NURSE_AT_REX, 0.8, () => {
      this.listening = true;
      const chest = this.rexGroup.localToWorld(new THREE.Vector3(0, 1.4, 0.6));
      [0, 0.9, 1.8].forEach((at) => this.later(at, () => {
        this.sfx.heartbeat();
        const s = this.screen(chest);
        this.hud.floatText(at === 0 ? '🩺' : '💓', s.x, s.y);
      }));
      this.later(2.6, () => {
        this.listening = false;
        this.walk(NURSE_HOME, 0.7, () => { this.busy = false; this.verdict(); });
      });
    });
  }

  verdict() {
    const s = this.game.state;
    const med = s.inventory.medicine || 0;
    const cost = STORE_ITEMS.find((i) => i.id === 'medicine')?.cost ?? 60;
    if (!this.game.needsMedicine()) {
      this.stage = 'end';
      this.sfx.happy();
      this.rex.play('cheer', 1.6, 'sit');
      this.say('Great news! Rex is healthy and strong 💪 Keep doing your tasks to keep him that way!',
        [{ label: 'Back to Rex', act: 'back', kind: 'green' }]);
      return;
    }
    const how = s.status === 'sick' ? 'Oh no, Rex is sick 🤒' : "Hmm, Rex isn't feeling his best 😕";
    if (!med) {
      this.stage = 'end';
      const coins = s.coins >= cost ? 'You have enough coins right now! 🪙' : 'Finish your tasks to earn coins! 🪙';
      this.say(`${how} He needs Dino Medicine 💊 to feel better. You can get it in the Reward Store for ${cost} coins. ${coins}`, [
        { label: '🛒 Go to Store', act: 'store' },
        { label: 'Back to Rex', act: 'back', kind: 'green' },
      ]);
      return;
    }
    this.stage = 'ask';
    this.say(`${how} You have Dino Medicine 💊 ×${med}. May I give Rex his medicine?`, [
      { label: 'Not now', act: 'care-no' },
      { label: 'Yes, please! 💊', act: 'care-yes', kind: 'green' },
    ]);
  }

  treat() {
    this.stage = 'treat';
    this.busy = true;
    this.say('Here we go… open wide, Rex! 💊');
    this.walk(NURSE_AT_REX, 0.8, () => {
      this.giving = true;
      const m = this.screen(this.mouth(this.rex));
      this.hud.floatText('💊', m.x, m.y);
      this.rex.play('eat', 1.0, 'sit');
      this.later(1.1, () => {
        this.giving = false;
        const r = this.game.medicine();
        this.sfx.revive();
        this.rex.play('cheer', 1.8, 'sit');
        const c = this.rexGroup.localToWorld(new THREE.Vector3(0, 1.6, 0.3));
        for (let i = 0; i < 6; i++) this.later(i * 0.12, () => this.burst(c.clone().add(new THREE.Vector3((Math.random() - 0.5), Math.random() * 0.8, 0.3)), 0xb6ffcf, 3, 1.4, 0.06, 0.7));
        this.walk(NURSE_HOME, 0.7, () => {
          this.busy = false;
          this.stage = 'end';
          this.say(r.ok
            ? 'All better! 💚 Rex feels great now. Remember: doing your tasks keeps him healthy!'
            : 'Rex is feeling better already! 💚',
          [{ label: 'Back to Rex', act: 'back', kind: 'green' }]);
        });
      });
    });
  }

  tick(dt, t) {
    const n = this.nurse.userData;
    const toRex = this.walking || this.listening || this.giving;
    const yaw = this.listening || this.giving ? 1.25 : this.walking ? (this.nurse.position.x < -0.5 ? 1.4 : 1.0) : 0.5;
    this.nurse.rotation.y += (yaw - this.nurse.rotation.y) * Math.min(1, dt * 6);
    n.body.position.y = this.walking ? Math.abs(Math.sin(t * 12)) * 0.06 : Math.sin(t * 2) * 0.01;
    // Right arm reaches out with the stethoscope / medicine.
    const reach = this.listening || this.giving ? -1.35 : 0;
    n.arms[1].rotation.x += (reach + (toRex ? 0 : Math.sin(t * 2) * 0.05) - n.arms[1].rotation.x) * Math.min(1, dt * 8);
    n.arms[0].rotation.x = this.walking ? Math.sin(t * 12) * 0.5 : Math.sin(t * 2 + 1) * 0.05;
    // Head bobs while she talks.
    if (this.talkT > 0) {
      this.talkT -= dt;
      n.head.rotation.z = Math.sin(t * 9) * 0.06;
      n.head.rotation.x = Math.sin(t * 7) * 0.04;
    } else {
      n.head.rotation.z *= 0.9;
      n.head.rotation.x *= 0.9;
    }
    if (!this.rex.actionUntil) this.rex.setMode(this.rexMode());
    this.rex.update(dt, t);
  }
}
