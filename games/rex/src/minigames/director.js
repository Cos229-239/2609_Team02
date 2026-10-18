// Runs the minigame flow: games menu → Rex runs at the camera → iris shutter
// closes on him → game scene → result card → iris back to the room.
//
// Embedded in the app, the host owns sessions and XP: we post `startGame`,
// it answers RexGame.launchGame({ ok, gameId, sessionId, seed, settings,
// baseXp, attempt }), and we post `gameFinished` with the outcome counters
// (the same ones the old Flutter games sent; the server validates them).
import { GAMES, GAME_IDS, GameHud, readSettings, readMultiplier, performance as perfOf, xpPreview, DIFFICULTIES, difficultyOf, practiceSettings } from './common.js';
import { RunGame } from './run.js';
import { MemoryGame } from './memory.js';
import { BalloonGame } from './balloons.js';
import { DanceGame } from './dance.js';
import { CARE_SCENES } from '../care/index.js';
import { CARE_INFO } from '../care/common.js';

const CLASSES = { jumpAndRun: RunGame, matchPairs: MemoryGame, balloonPopper: BalloonGame, memoryRun: DanceGame };
const MAX_ATTEMPTS = 2; // MiniGameSession.maxAttempts
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export class Director {
  constructor({ world, game, bridge, sfx, toast, embedded }) {
    Object.assign(this, { world, game, bridge, sfx, toast, embedded });
    this.layer = $('#gameLayer');
    this.hud = new GameHud(this.layer);
    this.irisEl = $('#iris');
    this.phase = 'idle';
    // Demo (browser) data; the app replaces it with setGames().
    this.games = embedded
      ? { bonus: [], settings: {}, enabled: true }
      : { bonus: [{ sessionId: 'demo-bonus', gameId: 'jumpAndRun', taskTitle: 'Make Bed', baseXp: 20 }], settings: {}, enabled: true };
  }

  get active() { return this.phase !== 'idle'; }

  setGames(data = {}) {
    this.games = { bonus: data.bonus || [], settings: data.settings || {}, enabled: data.enabled !== false };
    this.renderBadge();
    if (!$('#gamesModal').hidden) this.renderMenu();
  }

  renderBadge() {
    const n = this.games.bonus.length;
    const b = $('#gamesBadge');
    b.hidden = !n;
    b.textContent = n;
  }

  openMenu() {
    if (this.active) return;
    this.renderMenu();
    $('#gamesModal').hidden = false;
    this.sfx.tap();
  }

  closeMenu() { $('#gamesModal').hidden = true; }

  renderMenu() {
    const bonus = this.games.bonus.filter((b) => GAMES[b.gameId]);
    $('#bonusList').innerHTML = bonus.length
      ? bonus.map((b) => {
        const g = GAMES[b.gameId];
        return `<button class="bonus-row" data-game="${b.gameId}" data-session="${esc(b.sessionId)}" style="--c:${g.color}">
          <span class="g-ico">${g.icon}</span>
          <span class="g-main"><b>${g.title}</b><small>Bonus for “${esc(b.taskTitle || 'a task')}” · up to ${this.maxMultLabel()} XP</small></span>
          <span class="btn green">Play</span></button>`;
      }).join('')
      : `<div class="empty small"><span class="big">📋</span>Finish a task and a grown-up's approval unlocks a bonus game!</div>`;
    $('#practiceDifficulty').innerHTML = this.difficultyPicker();
    $('#practiceGrid').innerHTML = GAME_IDS.map((id) => {
      const g = GAMES[id];
      return `<button class="practice-tile" data-game="${id}" style="--c:${g.color}"><span class="g-ico">${g.icon}</span><b>${g.title}</b><small>${g.blurb}</small></button>`;
    }).join('');
  }

  get difficulty() { return difficultyOf(this.game.state.settings.practiceDifficulty).id; }

  difficultyPicker() {
    const cur = this.difficulty;
    return DIFFICULTIES.map((d) => `<button class="${d.id === cur ? 'on' : ''}" data-game-act="diff-${d.id}" aria-pressed="${d.id === cur}"><span>${d.icon}</span>${d.label}</button>`).join('');
  }

  setDifficulty(id) {
    const d = difficultyOf(id).id;
    if (d === this.difficulty) return;
    this.game.state.settings.practiceDifficulty = d;
    this.game.save();
    this.sfx.tap();
    if (!$('#gamesModal').hidden) $('#practiceDifficulty').innerHTML = this.difficultyPicker();
    // On a practice result card: the next "Play again" uses the new level.
    const c = this.current;
    if (c && !c.rewarded && this.phase === 'result') {
      c.difficulty = d;
      c.settings = practiceSettings(c.gameId, d);
      this.showResult();
    }
  }

  maxMultLabel() {
    const m = readMultiplier(this.games.settings);
    return `${(m.maxPct / 100).toString()}×`;
  }

  // ---------------------------------------------------------------- care scenes

  // Feed / Play / Wash / Medicine: Rex bounces, the shutter closes on him and
  // a care scene opens. Returns a FAIL reason when the scene can't open.
  startCare(act) {
    if (this.active || !CARE_SCENES[act]) return 'busy';
    const reason = this.game.careCheck(act);
    if (reason) return reason;
    this.closeMenu();
    this.phase = 'launching';
    this.trans = null;
    this.payload = null;
    this.entered = false;
    document.body.classList.add('launching');
    const rex = this.world.rex;
    rex.actionUntil = null;
    rex.play('bounce', 1.6, 'bounce');
    this.sfx.happy();
    setTimeout(() => {
      if (this.phase !== 'launching') return;
      this.sfx.iris();
      this.iris(0, this.world.rexHeadScreen(), 560).then(() => this.enterCare(act));
    }, 750);
    return null;
  }

  enterCare(act) {
    if (this.phase !== 'launching') return;
    const info = CARE_INFO[act];
    this.current = { care: act, rewarded: false };
    this.layer.querySelector('#gameResult').hidden = true;
    this.hud.setExtra('');
    this.hud.setProgress(null);
    this.hud.setStats('');
    this.hud.clearCare();
    this.hud.setHeader(info.icon, info.title, info.color);
    this.instance = new CARE_SCENES[act]({
      game: this.game,
      hud: this.hud,
      sfx: this.sfx,
      onFinish: (r) => this.careFinish(r),
    });
    this.world.setOverlay(this.instance);
    this.resetRoomRex();
    document.body.classList.remove('launching');
    document.body.classList.add('in-game');
    this.phase = 'playing';
    this.iris(1.5, null, 520).then(() => this.instance?.start());
  }

  // r: { icon, title, line, gain } shows a card; { back: true } goes home.
  careFinish(r = {}) {
    if (this.phase !== 'playing') return;
    if (r.back) { this.backToRoom(); return; }
    this.phase = 'result';
    this.hud.clearCare();
    this.hud.setProgress(null);
    const el = this.layer.querySelector('#gameResult');
    el.innerHTML = `<div class="result-card">
      <div class="care-big">${r.icon || '⭐'}</div>
      <h3>${esc(r.title || 'Great job!')}</h3>
      <p class="result-line">${esc(r.line || '')}</p>
      ${r.gain ? `<div class="care-gain">${r.gain}</div>` : ''}
      <div class="result-actions"><button class="btn green" data-game-act="back">Back to Rex</button></div></div>`;
    el.hidden = false;
  }

  pointerMove(x, y) {
    if (this.phase === 'playing') this.instance?.pointerMove?.(x, y);
  }

  pointerUp(x, y) {
    if (this.phase === 'playing') this.instance?.pointerUp?.(x, y);
  }

  // ---------------------------------------------------------------- launch

  choose(gameId, sessionId) {
    if (this.active || !CLASSES[gameId]) return;
    const s = this.game.state;
    if (s.status === 'fossil') { this.toast('Rex is a fossil… dig him up first! ⛏️', 'bad'); return; }
    if (s.sleeping) { this.toast('Shh… wake Rex up to play! ☀️', 'bad'); return; }
    this.closeMenu();
    this.phase = 'launching';
    this.pending = { gameId, sessionId: sessionId || null };
    this.payload = null;
    this.entered = false;
    this.trans = { t: 0, irisStarted: false, closed: false };
    this.sfx.roar();
    this.world.rex.setMode('run');
    this.world.rex.actionUntil = null;
    document.body.classList.add('launching');
    if (this.embedded) {
      this.bridge.post('startGame', { gameId, sessionId: sessionId || null });
    } else {
      const bonus = this.games.bonus.find((b) => b.sessionId === sessionId);
      setTimeout(() => this.launch({
        ok: true, gameId, sessionId: sessionId || null, seed: Math.floor(Math.random() * 2 ** 31),
        settings: this.games.settings, baseXp: bonus?.baseXp || 0, attempt: 1,
      }), 400);
    }
  }

  // Host answer to startGame.
  launch(payload) {
    if (this.phase !== 'launching') return;
    if (!payload?.ok) {
      this.abortLaunch(payload?.error || "Couldn't start the game.");
      return;
    }
    this.payload = payload;
    this.tryEnter();
  }

  abortLaunch(error) {
    this.toast(error, 'bad');
    const done = () => {
      this.resetRoomRex();
      this.phase = 'idle';
      document.body.classList.remove('launching');
    };
    if (this.trans?.closed) this.iris(1, null, 450).then(done);
    else { this.irisStop = true; this.irisR = 1.5; this.setIris(1.5); done(); }
  }

  tryEnter() {
    if (!this.payload || !this.trans?.closed || this.entered) return;
    this.entered = true;
    const p = this.payload;
    // Practice uses the child's chosen difficulty; bonus games use the
    // parent's settings (the server checks those results).
    const difficulty = p.sessionId ? null : this.difficulty;
    const settings = difficulty ? practiceSettings(p.gameId, difficulty) : readSettings(p.gameId, p.settings || {});
    this.current = {
      ...p,
      difficulty,
      settings,
      multiplier: readMultiplier(p.settings || {}),
      rewarded: !!p.sessionId,
    };
    this.layer.querySelector('#gameResult').hidden = true;
    this.hud.setExtra('');
    this.hud.setProgress(null);
    this.instance = new CLASSES[p.gameId]({
      settings,
      seed: p.seed >>> 0,
      hud: this.hud,
      sfx: this.sfx,
      onFinish: (r) => this.finish(r),
    });
    this.world.setOverlay(this.instance);
    this.resetRoomRex();
    document.body.classList.remove('launching');
    document.body.classList.add('in-game');
    this.phase = 'playing';
    $('#irisLabel').hidden = true;
    this.iris(1.5, null, 520).then(() => this.instance?.start());
  }

  resetRoomRex() {
    const w = this.world;
    w.rexHolder.position.set(0, 0, 0);
    w.rex.baseYaw = -0.3;
    w.rex.setMode('idle');
    w.applyState(this.game.state);
  }

  // ---------------------------------------------------------------- frame

  update(dt) {
    if (this.phase !== 'launching' || !this.trans || this.trans.closed) return;
    // Rex hops out of bed and charges the camera.
    const tr = this.trans;
    tr.t += dt;
    const w = this.world;
    const rex = w.rex;
    rex.setMode('run');
    rex.baseYaw += (0 - rex.baseYaw) * Math.min(1, dt * 8);
    const h = w.rexHolder;
    h.position.z += dt * (2.5 + tr.t * 7);
    h.position.y = Math.min(0.35, tr.t * 1.2);
    if (tr.t > 0.55 && !tr.irisStarted) {
      tr.irisStarted = true;
      this.sfx.iris();
      const at = w.rexHeadScreen();
      this.iris(0, at, 560).then(() => {
        if (this.phase !== 'launching' || this.trans !== tr) return;
        tr.closed = true;
        if (!this.payload) $('#irisLabel').hidden = false;
        this.tryEnter();
      });
    }
  }

  pointer(x, y) {
    if (this.phase === 'playing') this.instance?.pointer(x, y);
  }

  act(name) {
    if (name === 'replay') this.instance?.replay?.();
    if (name.startsWith('care-')) { if (this.phase === 'playing') this.instance?.act?.(name.slice(5)); return; }
    if (name === 'store') { this.backToRoom(); this.onGoStore?.(); return; }
    if (name === 'quit') this.quit();
    if (name === 'back') this.backToRoom();
    if (name === 'again') this.playAgain();
    if (name === 'leave') this.leave();
    if (name === 'stay') this.layer.querySelector('#gameConfirm').hidden = true;
    if (name.startsWith('diff-')) this.setDifficulty(name.slice(5));
  }

  // ---------------------------------------------------------------- results

  finish(result) {
    if (this.phase !== 'playing') return;
    this.phase = 'result';
    const c = this.current;
    const perf = perfOf(c.gameId, result.details);
    const preview = xpPreview(c.baseXp || 0, perf, c.multiplier);
    this.lastResult = { ...result, perf, preview };
    if (this.embedded) {
      this.bridge.post('gameFinished', {
        gameId: c.gameId, sessionId: c.sessionId, details: result.details,
        completed: !!result.completed, elapsedMs: result.elapsedMs, performance: perf,
      });
    } else if (c.rewarded) {
      this.game.addXp(Math.max(0, preview.xp - (c.baseXp || 0)));
    }
    this.showResult();
  }

  // Host confirmation after MiniGameService.finish (preview numbers).
  gameResult(data = {}) {
    if (!this.lastResult) return;
    this.lastResult.host = data;
    this.showResult();
  }

  showResult() {
    const c = this.current, r = this.lastResult;
    const d = r.details;
    const line = {
      jumpAndRun: `🏃 ${d.distance} m of ${d.runLength} m · ⭐ ${d.collected}/${d.collectibles}`,
      matchPairs: `🃏 ${d.matched}/${d.pairs} pairs found`,
      balloonPopper: `🦴 ${d.popped}/${d.target} bones`,
      memoryRun: `🪩 ${d.reached}/${d.target} dance steps`,
    }[c.gameId];
    const stars = r.perf >= 0.99 ? 3 : r.perf >= 0.5 ? 2 : r.perf > 0 ? 1 : 0;
    let xp;
    if (!c.rewarded) {
      const d = difficultyOf(c.difficulty);
      xp = `<p class="xp-line muted">${d.icon} ${d.label} practice: no XP. Finish tasks to unlock bonus games!</p>
        <div class="seg diff-seg result-diff">${this.difficultyPicker()}</div>`;
    }
    else if (r.host?.error) xp = `<p class="xp-line bad">${esc(r.host.error)}</p>`;
    else {
      const pct = r.host?.multiplierPct ?? r.preview.pct;
      const total = r.host?.finalXp ?? r.preview.xp;
      const base = c.baseXp || 0;
      // The task's own XP was paid at approval; the game adds the difference.
      const bonus = Math.max(0, total - base);
      const label = `${(pct / 100).toString()}×`;
      xp = `<p class="xp-line">${bonus > 0 ? `⭐ <b>+${bonus} bonus XP</b>` : 'No bonus XP this time'} <span class="mult">${label}</span></p>
        <p class="xp-note">“${esc(c.taskTitle || this.bonusTitle(c.sessionId))}”: ${base} XP × ${label} = ${total} XP.
        ${this.embedded ? 'You and Rex level up together!' : 'Demo XP added to Rex.'}</p>`;
    }
    const el = this.layer.querySelector('#gameResult');
    el.innerHTML = `<div class="result-card">
      <div class="result-stars">${'⭐'.repeat(stars)}${'☆'.repeat(3 - stars)}</div>
      <h3>${r.completed ? 'Amazing!' : r.perf >= 0.5 ? 'Great try!' : 'Nice try!'}</h3>
      <p class="result-line">${line}</p>
      ${xp}
      <div class="result-actions">
        ${c.rewarded ? '' : '<button class="btn" data-game-act="again">Play again</button>'}
        <button class="btn green" data-game-act="back">Back to Rex</button>
      </div></div>`;
    el.hidden = false;
  }

  bonusTitle(sessionId) {
    return this.games.bonus.find((b) => b.sessionId === sessionId)?.taskTitle || 'your task';
  }

  quit() {
    // Care scenes: nothing is used up until the end, so just go home.
    if (this.phase !== 'playing' || this.current?.care) { this.backToRoom(); return; }
    const c = this.current;
    const last = c.rewarded && (c.attempt || 1) >= MAX_ATTEMPTS;
    const msg = !c.rewarded
      ? 'Rex will run back to his room.'
      : last ? 'If you leave now, this bonus game is gone.' : 'You can start this bonus game one more time later.';
    // An in-page card: the app's WebView doesn't show window.confirm().
    const el = this.layer.querySelector('#gameConfirm');
    el.innerHTML = `<div class="result-card confirm-card">
      <h3>Leave the game?</h3>
      <p class="result-line">${msg}</p>
      <div class="result-actions">
        <button class="btn" data-game-act="stay">Keep playing</button>
        <button class="btn green" data-game-act="leave">Leave</button>
      </div></div>`;
    el.hidden = false;
    this.leaveIsSkip = c.rewarded && last;
  }

  leave() {
    this.layer.querySelector('#gameConfirm').hidden = true;
    if (this.phase !== 'playing') return;
    const c = this.current;
    if (this.leaveIsSkip && this.embedded) this.bridge.post('skipGame', { sessionId: c.sessionId });
    this.backToRoom();
  }

  playAgain() {
    const c = this.current;
    if (!c || c.rewarded) return;
    this.layer.querySelector('#gameResult').hidden = true;
    this.instance?.dispose();
    this.instance = new CLASSES[c.gameId]({
      settings: c.settings, seed: Math.floor(Math.random() * 2 ** 31), hud: this.hud, sfx: this.sfx,
      onFinish: (r) => this.finish(r),
    });
    this.world.setOverlay(this.instance);
    this.phase = 'playing';
    this.instance.start();
  }

  backToRoom() {
    if (this.phase === 'idle' || this.leaving) return;
    this.leaving = true;
    this.iris(0, null, 420).then(() => {
      this.instance?.dispose();
      this.instance = null;
      this.world.setOverlay(null);
      this.layer.querySelector('#gameResult').hidden = true;
      this.layer.querySelector('#gameConfirm').hidden = true;
      this.hud.clearCare();
      this.hud.setStats('');
      this.current = null;
      document.body.classList.remove('in-game');
      this.resetRoomRex();
      this.phase = 'idle';
      this.entered = false;
      this.lastResult = null;
      this.leaving = false;
      this.world.rex.play('happy', 1.4, this.game.state.status === 'sick' ? 'sick' : 'idle');
      return this.iris(1.5, null, 520);
    });
  }

  // ---------------------------------------------------------------- iris

  setIris(r, at) {
    const el = this.irisEl;
    if (at) {
      el.style.setProperty('--ix', at.x + 'px');
      el.style.setProperty('--iy', at.y + 'px');
    }
    const maxR = Math.hypot(innerWidth, innerHeight);
    el.style.setProperty('--ir', Math.max(0, r) * maxR + 'px');
    el.hidden = r >= 1.49;
    el.classList.toggle('blocking', r < 1.49);
  }

  // Animate the shutter radius to `to` (0 closed … 1.5 fully open).
  iris(to, at, ms) {
    this.irisStop = false;
    const el = this.irisEl;
    if (!at) at = { x: innerWidth / 2, y: innerHeight / 2 };
    const from = this.irisR ?? 1.5;
    if (to < from) el.hidden = false;
    return new Promise((resolve) => {
      const t0 = performance.now();
      const step = (now) => {
        if (this.irisStop) return resolve();
        const k = Math.min(1, (now - t0) / ms);
        const e = to < from ? k * k : 1 - (1 - k) * (1 - k);
        this.irisR = from + (to - from) * e;
        this.setIris(this.irisR, at);
        if (k < 1) requestAnimationFrame(step);
        else resolve();
      };
      requestAnimationFrame(step);
    });
  }
}
