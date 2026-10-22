// Game state + rules. Pure logic: no DOM, no three.js. The UI subscribes via
// onChange/onEvent and calls the action methods.
import { DEMO_TASKS, STORE_ITEMS } from './data.js';

const KEY = 'famotive.rex.v1';

// Need loss per (game) hour. Sleeping restores energy instead.
const DECAY = { hunger: 4, fun: 4, clean: 2.5, energy: 3 };
const SLEEP_ENERGY_GAIN = 18;
const HEALTH_LOSS = 2; // per hour while neglected (≈2 days to sick, ≈3 to fossil)
const HEALTH_GAIN = 3; // per hour while cared for
const SICK_BELOW = 40;
const RECOVER_ABOVE = 60;
const DIGS_TO_REVIVE = 3;
const NEED_BOOST_PER_TASK = 20;

// Shared with the app: one level per 500 XP (AppConstants.levelUpXpThreshold).
export const LEVEL_XP = 500;
export const xpToNext = () => LEVEL_XP;

// Famotive tasks don't carry a "care" stat, so infer one from the title.
export function careFor(title = '') {
  const t = title.toLowerCase();
  if (/(clean|sweep|trash|laundry|wash|dish|tidy|vacuum|brush|bath)/.test(t)) return 'clean';
  if (/(dinner|lunch|breakfast|cook|feed|snack|table|grocer)/.test(t)) return 'hunger';
  if (/(bed|sleep|homework|read|study|nap)/.test(t)) return 'energy';
  return 'fun';
}

function freshState(embedded) {
  return {
    name: 'Rex',
    level: 1,
    xp: 20,
    coins: 60,
    needs: { hunger: 70, fun: 75, clean: 65, energy: 80 },
    health: 100,
    status: 'healthy', // healthy | sick | fossil
    sleeping: false,
    digs: 0,
    inventory: { treat: 2, soap: 1, medicine: 0 },
    owned: {},
    // Embedded in the app, real tasks arrive through setTasks().
    tasks: embedded ? [] : DEMO_TASKS.map((t) => ({ ...t })),
    // Approved tasks already claimed here, so a refresh from the app (which
    // only knows pending/completed/approved) doesn't offer them again.
    claimedIds: [],
    lastTick: Date.now(),
    settings: { sound: true, pixel: 2, speed: 1, demo: !embedded, practiceDifficulty: 'medium' },
    seenHint: false,
  };
}

const clamp = (v) => Math.max(0, Math.min(100, v));

export class Game {
  // player: separate save slot per child; embedded: running inside the app.
  constructor({ player = '', embedded = false } = {}) {
    this.key = player ? `${KEY}.${player}` : KEY;
    this.embedded = embedded;
    this.listeners = new Set();
    this.eventListeners = new Set();
    this.state = this.load();
    this.catchUp();
  }

  load() {
    try {
      const raw = localStorage.getItem(this.key);
      if (raw) {
        const s = JSON.parse(raw);
        const base = freshState(this.embedded);
        return { ...base, ...s, needs: { ...base.needs, ...s.needs }, inventory: { ...base.inventory, ...s.inventory }, settings: { ...base.settings, ...s.settings } };
      }
    } catch (_) { /* storage unavailable */ }
    return freshState(this.embedded);
  }

  save() {
    try { localStorage.setItem(this.key, JSON.stringify(this.state)); } catch (_) { /* ignore */ }
  }

  onChange(fn) { this.listeners.add(fn); }
  onEvent(fn) { this.eventListeners.add(fn); }
  changed() { this.save(); this.listeners.forEach((f) => f(this.state)); }
  emit(type, data = {}) { this.eventListeners.forEach((f) => f(type, data)); }

  // Applies time that passed while the app was closed (real time, unscaled
  // speed so a demo "turbo" doesn't fossilise Rex overnight).
  catchUp() {
    const hours = (Date.now() - this.state.lastTick) / 3.6e6;
    if (hours > 0.01) this.advance(Math.min(hours, 24 * 7));
    this.state.lastTick = Date.now();
  }

  tick(realSeconds) {
    const s = this.state;
    s.lastTick = Date.now();
    this.advance((realSeconds / 3600) * s.settings.speed);
    this.changed();
  }

  advance(hours) {
    const s = this.state;
    if (s.status === 'fossil') return;
    // Step in small slices so status transitions happen at the right moment.
    let left = hours;
    while (left > 0) {
      const h = Math.min(left, 0.25);
      left -= h;
      const n = s.needs;
      n.hunger = clamp(n.hunger - DECAY.hunger * h * (s.sleeping ? 0.5 : 1));
      n.fun = clamp(n.fun - DECAY.fun * h * (s.sleeping ? 0.3 : 1));
      n.clean = clamp(n.clean - DECAY.clean * h);
      n.energy = clamp(s.sleeping ? n.energy + SLEEP_ENERGY_GAIN * h : n.energy - DECAY.energy * h);
      if (s.sleeping && n.energy >= 100) {
        s.sleeping = false;
        this.emit('woke');
      }
      const avg = (n.hunger + n.fun + n.clean + n.energy) / 4;
      const neglected = avg < 35 || Math.min(n.hunger, n.clean) <= 5;
      s.health = clamp(s.health + (neglected ? -HEALTH_LOSS : avg > 50 ? HEALTH_GAIN : 0) * h);
      this.updateStatus();
      if (s.status === 'fossil') return;
    }
  }

  updateStatus() {
    const s = this.state;
    const prev = s.status;
    if (s.status !== 'fossil') {
      if (s.health <= 0) {
        s.status = 'fossil';
        s.sleeping = false;
        s.digs = 0;
      } else if (s.health < SICK_BELOW) s.status = 'sick';
      else if (s.health > RECOVER_ABOVE) s.status = 'healthy';
    }
    if (prev !== s.status) this.emit('status', { from: prev, to: s.status });
  }

  get lowestNeed() {
    const n = this.state.needs;
    return Object.keys(n).reduce((a, b) => (n[a] <= n[b] ? a : b));
  }

  // ---- Tasks -------------------------------------------------------------

  markDone(id) {
    const t = this.state.tasks.find((x) => x.id === id);
    if (!t || t.status !== 'pending') return;
    // Photo tasks stay "To Do" until the app's camera screen sends the photo;
    // the next setTasks() moves them to Waiting.
    if (t.needsPhoto && this.embedded) {
      this.emit('photoNeeded', { task: t });
      return;
    }
    t.status = 'completed';
    if (t.needsPhoto) t.photoSent = true; // demo: pretend the photo went
    this.emit('taskCompleted', { task: t });
    this.changed();
  }

  approve(id) {
    const t = this.state.tasks.find((x) => x.id === id);
    if (!t || t.status !== 'completed') return;
    t.status = 'approved';
    this.emit('taskApproved', { task: t });
    this.changed();
  }

  claim(id) {
    const s = this.state;
    const t = s.tasks.find((x) => x.id === id);
    if (!t || t.status !== 'approved') return;
    t.status = 'claimed';
    s.claimedIds = [...s.claimedIds.filter((x) => x !== t.id), t.id].slice(-500);
    s.coins += t.coinReward;
    this.addXp(t.rewardXp);
    const care = t.care || careFor(t.title);
    if (s.status === 'fossil') {
      s.digs += 1;
      this.emit('dig', { digs: s.digs, needed: DIGS_TO_REVIVE });
      if (s.digs >= DIGS_TO_REVIVE) this.revive();
    } else {
      s.needs[care] = clamp(s.needs[care] + NEED_BOOST_PER_TASK);
      s.needs.fun = clamp(s.needs.fun + 5);
      s.health = clamp(s.health + 6);
      this.updateStatus();
    }
    this.emit('claimed', { task: t, care });
    this.changed();
  }

  addXp(amount) {
    // In the app, XP is the child's real XP (setPlayer); nothing is added here.
    if (this.embedded) return;
    const s = this.state;
    s.xp += amount;
    while (s.xp >= xpToNext(s.level)) {
      s.xp -= xpToNext(s.level);
      s.level += 1;
      this.emit('levelUp', { level: s.level });
    }
  }

  // The child's real total XP from the app: Rex shares the child's level.
  setPlayer({ xp } = {}) {
    if (typeof xp !== 'number' || !Number.isFinite(xp)) return;
    const s = this.state;
    const level = 1 + Math.floor(Math.max(0, xp) / LEVEL_XP);
    const leveled = this.playerSynced && level > s.level;
    s.level = level;
    s.xp = Math.max(0, xp) % LEVEL_XP;
    this.playerSynced = true;
    if (leveled) this.emit('levelUp', { level });
    this.changed();
  }

  revive() {
    const s = this.state;
    s.status = 'healthy';
    s.health = 65;
    s.needs = { hunger: 55, fun: 60, clean: 55, energy: 60 };
    s.digs = 0;
    this.emit('revived');
    this.emit('status', { from: 'fossil', to: 'healthy' });
  }

  refillDemoTasks() {
    this.state.tasks = DEMO_TASKS.map((t) => ({ ...t, id: t.id + '-' + Date.now().toString(36), status: 'pending' }));
    this.changed();
  }

  // Replace tasks with ones from the Famotive app (bridge).
  setTasks(list) {
    const claimed = new Set(this.state.claimedIds);
    this.state.tasks = list.map((t) => ({
      id: String(t.id),
      title: t.title,
      icon: t.icon || '⭐',
      rewardXp: t.rewardXp ?? 10,
      coinReward: t.coinReward ?? 10,
      care: t.care || careFor(t.title),
      needsPhoto: !!t.needsPhoto,
      photoSent: !!t.photoSent,
      photoCheck: !!t.photoCheck,
      status: t.status === 'approved' && claimed.has(String(t.id)) ? 'claimed' : t.status || 'pending',
    }));
    this.state.settings.demo = false;
    this.changed();
  }

  // ---- Store + care actions ---------------------------------------------

  // Demo / QA builds: own every Rex item (toys, decor, cosmetics, pets) and
  // keep the care items stocked, so testers can try everything without
  // saving up coins. Family rewards are real-world and stay in the app.
  unlockAll(stock = 99) {
    const s = this.state;
    for (const item of STORE_ITEMS) {
      if (item.kind === 'consumable') s.inventory[item.id] = Math.max(s.inventory[item.id] || 0, stock);
      else if (item.kind !== 'family') s.owned[item.id] = true;
    }
    this.changed();
  }


  buy(itemId) {
    const s = this.state;
    const item = STORE_ITEMS.find((i) => i.id === itemId);
    if (!item) return { ok: false, reason: 'missing' };
    if (item.kind !== 'consumable' && item.kind !== 'family' && s.owned[item.id]) return { ok: false, reason: 'owned' };
    if (s.coins < item.cost) return { ok: false, reason: 'coins', need: item.cost - s.coins };
    s.coins -= item.cost;
    if (item.kind === 'consumable') s.inventory[item.id] = (s.inventory[item.id] || 0) + 1;
    else if (item.kind === 'family') this.emit('rewardRequested', { item });
    else s.owned[item.id] = true;
    this.emit('bought', { item });
    this.changed();
    return { ok: true, item };
  }

  // Cosmetics can be taken off and put back on. Returns the new state.
  toggleWear(id) {
    const s = this.state;
    if (!s.owned[id]) return false;
    s.wearing = { ...s.wearing, [id]: s.wearing?.[id] === false };
    this.changed();
    return s.wearing[id];
  }

  canAct() {
    return this.state.status !== 'fossil';
  }

  // Can this care scene open? Returns a FAIL reason, or null. Nothing is
  // used up here: the item is spent when the child finishes the scene.
  careCheck(act) {
    const s = this.state;
    if (!this.canAct()) return 'fossil';
    if (s.sleeping) return 'sleeping';
    if (act === 'feed') {
      if (s.needs.hunger > 95) return 'full';
      if (!s.inventory.treat) return 'noTreat';
    } else if (act === 'play') {
      if (!s.owned.ball) return 'noBall';
      if (s.status === 'sick') return 'sick';
      if (s.needs.energy < 15) return 'tired';
    } else if (act === 'wash') {
      if (!s.inventory.soap) return 'noSoap';
    }
    // The nurse always sees Rex, medicine or not.
    return null;
  }

  // The nurse's check-up: sick, or health low enough to treat.
  needsMedicine() {
    return this.state.status === 'sick' || this.state.health < 60;
  }

  feed() {
    const s = this.state;
    if (!this.canAct()) return { ok: false, reason: 'fossil' };
    if (s.sleeping) return { ok: false, reason: 'sleeping' };
    if (s.needs.hunger > 95) return { ok: false, reason: 'full' };
    if (!s.inventory.treat) return { ok: false, reason: 'noTreat' };
    s.inventory.treat -= 1;
    s.needs.hunger = clamp(s.needs.hunger + 35);
    s.health = clamp(s.health + 4);
    this.updateStatus();
    this.changed();
    return { ok: true };
  }

  playBall() {
    const s = this.state;
    if (!this.canAct()) return { ok: false, reason: 'fossil' };
    if (s.sleeping) return { ok: false, reason: 'sleeping' };
    if (!s.owned.ball) return { ok: false, reason: 'noBall' };
    if (s.status === 'sick') return { ok: false, reason: 'sick' };
    if (s.needs.energy < 15) return { ok: false, reason: 'tired' };
    s.needs.fun = clamp(s.needs.fun + 25);
    s.needs.energy = clamp(s.needs.energy - 10);
    s.needs.hunger = clamp(s.needs.hunger - 5);
    this.changed();
    return { ok: true };
  }

  wash() {
    const s = this.state;
    if (!this.canAct()) return { ok: false, reason: 'fossil' };
    if (s.sleeping) return { ok: false, reason: 'sleeping' };
    if (!s.inventory.soap) return { ok: false, reason: 'noSoap' };
    s.inventory.soap -= 1;
    s.needs.clean = clamp(s.needs.clean + 40);
    s.health = clamp(s.health + 4);
    this.updateStatus();
    this.changed();
    return { ok: true };
  }

  medicine() {
    const s = this.state;
    if (!this.canAct()) return { ok: false, reason: 'fossil' };
    if (!s.inventory.medicine) return { ok: false, reason: 'noMedicine' };
    if (!this.needsMedicine()) return { ok: false, reason: 'healthy' };
    s.inventory.medicine -= 1;
    s.health = clamp(Math.max(s.health + 35, RECOVER_ABOVE + 1));
    this.updateStatus();
    this.changed();
    return { ok: true };
  }

  toggleSleep() {
    const s = this.state;
    if (!this.canAct()) return { ok: false, reason: 'fossil' };
    s.sleeping = !s.sleeping;
    this.changed();
    return { ok: true, sleeping: s.sleeping };
  }

  pet() {
    const s = this.state;
    if (!this.canAct() || s.sleeping) return false;
    const now = Date.now();
    if (this.lastPet && now - this.lastPet < 3000) return false;
    this.lastPet = now;
    s.needs.fun = clamp(s.needs.fun + 3);
    this.changed();
    return true;
  }

  // ---- Settings / debug --------------------------------------------------

  setSetting(k, v) {
    this.state.settings[k] = v;
    this.changed();
  }

  debugSick() {
    const s = this.state;
    s.status !== 'fossil' && Object.assign(s, { health: 30 });
    s.needs.hunger = 15;
    s.needs.clean = 10;
    this.updateStatus();
    this.changed();
  }

  debugFossil() {
    this.state.health = 0;
    this.updateStatus();
    this.changed();
  }

  reset() {
    try { localStorage.removeItem(this.key); } catch (_) { /* ignore */ }
    this.state = freshState(this.embedded);
    this.emit('status', { from: 'any', to: 'healthy' });
    this.changed();
  }
}

export { DIGS_TO_REVIVE };
