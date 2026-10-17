// Glue: game state ⇄ 3D world ⇄ HUD/panels, swipe navigation, and the
// bridge the Famotive Flutter app can use when embedding this in a WebView.
import { World } from './world.js';
import { Game, xpToNext, DIGS_TO_REVIVE } from './game.js';
import { STORE_ITEMS, STORE_TABS, CARE } from './data.js';
import { sfx, unlockAudio, setSound } from './audio.js';
import { renderIcons } from './icons.js';
import { Director } from './minigames/director.js';

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const params = new URLSearchParams(location.search);
// Running inside the Famotive app: the WebView injects window.REX_EMBED
// ({ player: childId }) before this script; ?embed=1&player=… does the same
// in a browser.
const embedCfg = window.REX_EMBED || null;
const embedded = !!embedCfg || params.get('embed') === '1';
const game = new Game({ player: embedCfg?.player || params.get('player') || '', embedded });
// Real-world rewards live in the app's own Rewards screen, so the game's
// store only sells Rex items when embedded.
const storeItems = embedded ? STORE_ITEMS.filter((i) => i.kind !== 'family') : STORE_ITEMS;
const storeTabs = embedded ? STORE_TABS.filter((t) => t.id !== 'family') : STORE_TABS;
if (embedded) document.body.classList.add('embedded');
// Applied once the bridge exists, below.
const initialInsets = embedCfg?.insets;
if (params.get('reset') === '1') game.reset();
if (params.get('demo') === '0') game.state.settings.demo = false;

const world = new World($('#scene'));
// Voxel thumbnails of Rex items (family rewards keep their emoji).
const icons = renderIcons(world, STORE_ITEMS.filter((i) => i.kind !== 'family').map((i) => i.id));
world.setPixel(game.state.settings.pixel);
setSound(game.state.settings.sound);

const ui = { page: 1, taskTab: 'todo', storeTab: 'all', confirmId: null, petUntil: 0 };
const wideMQ = window.matchMedia('(min-width: 1100px) and (min-height: 560px)');
const isWide = () => wideMQ.matches;

// ---------------------------------------------------------------- helpers

// Centre-screen notice card: big emoji, the message, colour by kind
// (good / bad / plain). One at a time, queued; tap to dismiss.
const notices = [];
let noticeTimer = 0;
const EMOJI = /(\p{Extended_Pictographic}(?:\uFE0F|\u200D\p{Extended_Pictographic})*)/u;

function toast(text, kind = '') {
  const last = notices[notices.length - 1];
  if (last && last.text === text) return; // ignore rapid repeats
  notices.push({ text, kind });
  if (notices.length > 3) notices.splice(0, notices.length - 3);
  if (!$('#notice').classList.contains('show')) showNotice();
}

function showNotice() {
  const n = notices.shift();
  const el = $('#notice');
  if (!n) { el.classList.remove('show'); return; }
  const m = n.text.match(EMOJI);
  const icon = m ? m[1] : n.kind === 'good' ? '🎉' : n.kind === 'bad' ? '🙈' : '🦖';
  const body = (m ? n.text.replace(m[1], '') : n.text).replace(/\s{2,}/g, ' ').trim();
  const ms = Math.min(4200, 1600 + body.length * 35);
  el.className = 'notice show ' + n.kind;
  el.innerHTML = `<div class="notice-card" role="status"><div class="notice-icon">${icon}</div>
    <p>${esc(body)}</p><i class="notice-timer" style="animation-duration:${ms}ms"></i></div>`;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(hideNotice, ms);
}

function hideNotice() {
  const el = $('#notice');
  clearTimeout(noticeTimer);
  el.classList.add('leaving');
  setTimeout(() => {
    el.classList.remove('leaving', 'show');
    if (notices.length) setTimeout(showNotice, 120);
  }, 220);
}

function fx(emoji, x, y, count = 1, spread = 60) {
  for (let i = 0; i < count; i++) {
    const el = document.createElement('div');
    el.className = 'fx';
    el.textContent = emoji;
    el.style.left = x + (Math.random() - 0.5) * spread + 'px';
    el.style.top = y + (Math.random() - 0.5) * spread * 0.4 + 'px';
    el.style.setProperty('--dx', (Math.random() - 0.5) * 60 + 'px');
    el.style.animationDelay = i * 0.08 + 's';
    $('#fx').append(el);
    setTimeout(() => el.remove(), 1600 + i * 80);
  }
}

function fxAtRex(emoji, count = 1, spread = 70) {
  if (!isWide() && ui.page !== 1) return;
  const p = world.rexHeadScreen();
  fx(emoji, p.x, p.y + 20, count, spread);
}

function flash() {
  const el = document.createElement('div');
  el.className = 'flash';
  document.body.append(el);
  setTimeout(() => el.remove(), 1000);
}

function baseMode() {
  const s = game.state;
  if (s.status === 'fossil') return 'idle';
  if (s.sleeping) return 'sleep';
  return s.status === 'sick' ? 'sick' : 'idle';
}

function animate(mode, seconds) {
  world.rex.play(mode, seconds, baseMode());
}

const needColor = (v) => (v > 60 ? 'linear-gradient(90deg,#2fd07a,#8cf0a0)' : v > 30 ? 'linear-gradient(90deg,#f7b928,#ffd86b)' : 'linear-gradient(90deg,#e5484d,#ff8a8a)');

// ---------------------------------------------------------------- render

function render() {
  const s = game.state;
  $$('[data-bind="coins"]').forEach((e) => (e.textContent = s.coins));
  $$('[data-bind="name"]').forEach((e) => (e.textContent = s.name));
  $$('[data-bind="level"]').forEach((e) => (e.textContent = s.level));
  $$('[data-bind="xp"]').forEach((e) => (e.textContent = s.xp));
  $$('[data-bind="xpNext"]').forEach((e) => (e.textContent = xpToNext(s.level)));
  $('#xpFill').style.width = (s.xp / xpToNext(s.level)) * 100 + '%';

  // Health + needs.
  const fossil = s.status === 'fossil';
  $('#healthFill').style.width = s.health + '%';
  $('#healthFill').style.background = needColor(s.health);
  const avg = (s.needs.hunger + s.needs.fun + s.needs.clean + s.needs.energy) / 4;
  $('#statusLabel').textContent = fossil ? 'Fossil' : s.status === 'sick' ? 'Sick' : s.sleeping ? 'Sleeping' : avg > 70 ? 'Happy' : avg < 40 ? 'Needs care' : 'Okay';
  $('#heartIcon').textContent = fossil ? '🦴' : s.status === 'sick' ? '💔' : '❤️';
  $('#heartIcon').classList.toggle('beat', !fossil && s.status !== 'sick');
  $('#needs').innerHTML = Object.entries(CARE).map(([k, c]) => {
    const v = Math.round(s.needs[k]);
    return `<div class="need ${v < 25 && !fossil ? 'low' : ''}" title="${c.label} ${v}%"><span>${c.icon}</span><div class="bar"><i style="width:${fossil ? 0 : v}%;background:${needColor(v)}"></i></div></div>`;
  }).join('');

  // Banner (only touched when its content changes, it has buttons).
  const banner = $('#banner');
  let cls = '', html = '';
  if (fossil) {
    cls = 'banner fossil';
    const digs = Array.from({ length: DIGS_TO_REVIVE }, (_, i) => `<span class="${i < s.digs ? 'on' : ''}">⛏️</span>`).join('');
    html = `🦴 Oh no! Rex turned into a fossil.<br>Finish ${DIGS_TO_REVIVE} tasks to dig him back up!<div class="digs">${digs}</div><button class="btn green" data-go="2">Go to Tasks</button>`;
  } else if (s.status === 'sick') {
    cls = 'banner sick';
    html = `🤒 Rex feels sick! Feed him, wash him, or give him medicine.${s.inventory.medicine ? '' : '<br><button class="btn" data-go="0">Get Medicine</button>'}`;
  }
  banner.hidden = !html;
  if (html) $('#swipeHint').hidden = true;
  if (banner.dataset.html !== html) {
    banner.dataset.html = html;
    banner.className = cls || 'banner';
    banner.innerHTML = html;
  }

  // Dock.
  const inv = s.inventory;
  $$('[data-count]').forEach((e) => {
    const n = inv[e.dataset.count] || 0;
    e.textContent = n;
    e.classList.toggle('zero', n === 0);
  });
  const dis = { feed: !inv.treat, play: !s.owned.ball || s.status === 'sick', wash: !inv.soap, medicine: !inv.medicine, sleep: false };
  $$('.act').forEach((b) => {
    const a = b.dataset.act;
    b.classList.toggle('disabled', fossil || dis[a] || (s.sleeping && a !== 'sleep'));
    b.classList.toggle('alert', a === 'medicine' && s.status === 'sick' && !!inv.medicine);
  });
  $('#sleepIcon').textContent = s.sleeping ? '☀️' : '🌙';
  $('#sleepLabel').textContent = s.sleeping ? 'Wake' : 'Sleep';

  renderTasks();
  renderStore();
  world.applyState(s);
}

function taskButton(t) {
  if (t.status === 'pending' && t.needsPhoto) return `<button class="btn photo" data-done="${esc(t.id)}">📸 Photo</button>`;
  if (t.status === 'pending') return `<button class="btn" data-done="${esc(t.id)}">Done!</button>`;
  if (t.status === 'completed' && t.photoSent) return `<span class="btn wait">${t.photoCheck ? '📸 Checking' : '📸 Sent'}</span>`;
  if (t.status === 'completed') return `<span class="btn wait">⏳ Waiting</span>`;
  if (t.status === 'approved') return `<button class="btn green claim" data-claim="${esc(t.id)}">Claim</button>`;
  return `<span class="btn wait">✓</span>`;
}

// Lists only re-render when their content changes: replacing buttons every
// game tick would swallow taps on iOS.
let tasksKey = '', storeKey = '';

function renderTasks(force) {
  const tasks = game.state.tasks;
  const key = JSON.stringify([ui.taskTab, tasks.map((t) => [t.id, t.status, t.needsPhoto, t.photoSent, t.photoCheck]), game.state.status, game.state.digs, game.state.settings.demo]);
  if (!force && key === tasksKey) return;
  tasksKey = key;
  const groups = {
    todo: tasks.filter((t) => t.status === 'pending' || t.status === 'approved').sort((a, b) => (a.status === 'approved' ? -1 : 0) - (b.status === 'approved' ? -1 : 0)),
    waiting: tasks.filter((t) => t.status === 'completed'),
    done: tasks.filter((t) => t.status === 'claimed'),
  };
  const ready = tasks.filter((t) => t.status === 'approved').length;
  const todo = groups.todo.length;
  const badge = $('#taskBadge');
  badge.hidden = !todo;
  badge.textContent = ready || todo;
  badge.classList.toggle('go', ready > 0);

  $('#taskTabs').innerHTML = [['todo', 'To Do'], ['waiting', 'Waiting'], ['done', 'Done']]
    .map(([k, l]) => `<button class="tab ${ui.taskTab === k ? 'on' : ''}" data-tasktab="${k}">${l}<span class="n">${groups[k].length}</span></button>`).join('');

  const list = groups[ui.taskTab];
  if (!list.length) {
    const msg = ui.taskTab === 'todo'
      ? `<span class="big">🎉</span>All done! Rex is proud of you.${game.state.settings.demo ? '<br><button class="btn" data-debug="tasks">Get more tasks (demo)</button>' : ''}`
      : ui.taskTab === 'waiting' ? '<span class="big">⏳</span>Nothing waiting for a grown-up.' : '<span class="big">📭</span>No finished tasks yet.';
    $('#taskList').innerHTML = `<div class="empty">${msg}</div>`;
  } else {
    $('#taskList').innerHTML = list.map((t) => {
      const care = CARE[t.care] || CARE.fun;
      return `<div class="task ${t.status === 'approved' ? 'ready' : ''} ${t.status === 'claimed' ? 'claimed' : ''}">
        <div class="task-icon">${esc(t.icon)}</div>
        <div class="task-main">
          <div class="task-title">${esc(t.title)}</div>
          <div class="task-meta"><span class="coin"></span><b>+${t.coinReward}</b><span>+${t.rewardXp} XP</span><span class="care-tag">${care.icon} ${care.label}</span></div>
        </div>
        ${taskButton(t)}
      </div>`;
    }).join('');
  }
  const s = game.state;
  $('#tasksFoot').textContent = s.status === 'fossil'
    ? `⛏️ Dig progress: ${s.digs} / ${DIGS_TO_REVIVE} — claim tasks to free Rex!`
    : ready ? `🎁 ${ready} reward${ready > 1 ? 's' : ''} ready to claim!` : 'Every task helps Rex stay healthy! 🦖';
}

function renderStore(force) {
  const s = game.state;
  const key = JSON.stringify([ui.storeTab, ui.confirmId, s.coins, s.owned, s.inventory, s.wearing]);
  if (!force && key === storeKey) return;
  storeKey = key;
  $('#storeTabs').innerHTML = storeTabs.map((t) => `<button class="tab ${ui.storeTab === t.id ? 'on' : ''}" data-storetab="${t.id}">${t.label}</button>`).join('');
  const items = storeItems.filter((i) => ui.storeTab === 'all' || i.cat === ui.storeTab);
  $('#storeGrid').innerHTML = items.map((i) => {
    const owned = i.kind !== 'consumable' && i.kind !== 'family' && s.owned[i.id];
    const qty = i.kind === 'consumable' ? s.inventory[i.id] || 0 : 0;
    const cant = !owned && s.coins < i.cost;
    const worn = i.id === 'hat' && owned ? (s.wearing?.hat !== false ? 'Wearing' : 'Off') : '';
    const confirm = ui.confirmId === i.id && !owned
      ? `<div class="confirm">${esc(i.desc)}<button class="btn green" data-buy="${i.id}">${i.kind === 'family' ? 'Ask' : 'Buy'} · ${i.cost}</button><button class="x" data-cancel>Cancel</button></div>`
      : '';
    return `<div class="item ${owned ? 'owned' : ''} ${cant ? 'cant' : ''}" style="--tint:${i.tint}" data-item="${i.id}" ${worn ? `data-worn="${worn}"` : ''} role="button" tabindex="0">
      ${qty ? `<span class="qty">×${qty}</span>` : ''}
      ${icons[i.id] ? `<img class="ico-img" src="${icons[i.id]}" alt="">` : `<span class="ico">${i.icon}</span>`}<span class="nm">${esc(i.name)}</span>
      <span class="price"><span class="coin"></span>${i.cost}</span>${confirm}
    </div>`;
  }).join('');
}

// ---------------------------------------------------------------- actions

const FAIL = {
  fossil: 'Rex is a fossil… finish tasks to dig him up! ⛏️',
  sleeping: 'Shh… Rex is sleeping 💤',
  full: 'Rex is full! 😋',
  noTreat: 'No treats left! Get Dino Treats in the Store 🍗',
  noBall: 'Get a Ball from the Store first ⚽',
  sick: 'Rex is too sick to play 🤒',
  tired: 'Rex is too tired. Let him sleep! 🌙',
  noSoap: 'No bubble bath! Get one in the Store 🧼',
  noMedicine: 'No medicine! Get some in the Store 💊',
  healthy: "Rex doesn't need medicine right now 💪",
};

function doAction(act) {
  let r;
  if (act === 'feed') r = game.feed();
  else if (act === 'play') r = game.playBall();
  else if (act === 'wash') r = game.wash();
  else if (act === 'medicine') r = game.medicine();
  else if (act === 'sleep') r = game.toggleSleep();
  if (!r?.ok) {
    sfx.bad();
    toast(FAIL[r?.reason] || 'Not now', 'bad');
    return;
  }
  if (act === 'feed') { animate('eat', 2.2); world.showFood(); sfx.chomp(); fxAtRex('🍗', 1); setTimeout(() => fxAtRex('😋', 1), 900); }
  if (act === 'play') { animate('play', 2.4); world.playBall(); sfx.happy(); fxAtRex('⭐', 4, 120); }
  if (act === 'wash') { animate('wash', 2.2); sfx.splash(); fxAtRex('🫧', 8, 140); }
  if (act === 'medicine') { animate('happy', 1.4); sfx.revive(); fxAtRex('✨', 6, 120); toast('Rex feels much better! 💚', 'good'); }
  if (act === 'sleep') { if (r.sleeping) toast('Goodnight, Rex 🌙'); else { animate('happy', 1); toast('Good morning! ☀️'); } }
}

function handleTap(x, y) {
  const hit = world.pick(x, y);
  if (hit === 'rex') {
    if (game.pet()) {
      ui.petUntil = performance.now() + 1800;
      animate('happy', 1.2);
      sfx.roar();
      fxAtRex('❤️', 3, 80);
    } else if (game.state.sleeping) toast('Zzz… 💤');
  } else if (hit === 'fossil') {
    world.shakeFossil();
    sfx.dig();
    toast('Finish tasks to dig Rex out! ⛏️');
  } else if (hit === 'ball') doAction('play');
  else if (hit === 'bowl') doAction('feed');
  // Rex glances toward where you tapped.
  world.rex.lookAt((x / window.innerWidth) * 2 - 1);
}

// ---------------------------------------------------------------- events

game.onChange(render);

game.onEvent((type, d) => {
  if (type === 'photoNeeded') {
    sfx.tap();
    toast('📸 Take a photo to show it\'s done!');
    bridge.post('taskCompleted', { taskId: d.task.id, photo: true });
  }
  if (type === 'taskCompleted') {
    sfx.tap();
    toast(d.task.needsPhoto ? `📸 Photo sent! A grown-up will check “${d.task.title}”` : `Nice! “${d.task.title}” sent to a grown-up ✅`, 'good');
    bridge.post('taskCompleted', { taskId: d.task.id });
    if (game.state.settings.demo) setTimeout(() => { game.approve(d.task.id); }, 2500);
  }
  if (type === 'taskApproved') toast(`👍 “${d.task.title}” approved — claim your reward!`, 'good');
  if (type === 'claimed') {
    sfx.coin();
    if (game.state.status !== 'fossil') { animate('happy', 1.4); fxAtRex(CARE[d.care]?.icon || '⭐', 3, 90); }
  }
  if (type === 'levelUp') { sfx.levelUp(); toast(`🎉 Level up! Rex is now level ${d.level}!`, 'good'); fxAtRex('⭐', 6, 140); }
  if (type === 'dig') { sfx.dig(); world.shakeFossil(); toast(`⛏️ Digging… ${d.digs} / ${d.needed}`); }
  if (type === 'revived') {
    sfx.revive();
    flash();
    setTimeout(() => { animate('happy', 2.5); fxAtRex('✨', 10, 160); }, 50);
    toast('🦖 Rex is back! Take good care of him!', 'good');
  }
  if (type === 'status') {
    if (d.to === 'sick' && d.from === 'healthy') { toast('🤒 Uh oh, Rex is getting sick!', 'bad'); sfx.sneeze(); }
    if (d.to === 'fossil') { toast('🦴 Rex turned into a fossil…', 'bad'); sfx.bad(); }
    if (d.to === 'healthy' && d.from === 'sick') toast('💚 Rex is healthy again!', 'good');
  }
  if (type === 'woke') { toast('☀️ Rex woke up full of energy!', 'good'); animate('happy', 1); }
  if (type === 'bought') {
    sfx.coin();
    const it = d.item;
    toast(it.kind === 'family' ? `📨 Asked a grown-up for “${it.name}”` : `${it.icon} Got ${it.name}!`, 'good');
    if (it.kind === 'family') bridge.post('rewardRequested', { rewardId: it.id });
  }
});

// ---------------------------------------------------------------- navigation

const track = $('#track');

function setPage(i, animate = true) {
  ui.page = Math.max(0, Math.min(2, i));
  track.classList.toggle('animating', animate);
  track.style.transform = `translate3d(${-ui.page * 33.3333}%,0,0)`;
  world.setPanelProgress(isWide() ? 0 : ui.page - 1);
  if (ui.page !== 1) hideHint();
}

function hideHint() {
  $('#swipeHint').hidden = true;
  if (!game.state.seenHint) { game.state.seenHint = true; game.save(); }
}

let drag = null;
let suppressClick = false;
// Taps are activated on pointerup (iOS Safari drops the synthetic click in
// this full-screen, always-animating page); the native click that may follow
// is swallowed so nothing fires twice.
let tapClickAt = -1e9;
let synthetic = false;

window.addEventListener('pointerdown', (e) => {
  unlockAudio();
  if (e.button !== 0) return;
  drag = { x: e.clientX, y: e.clientY, t: performance.now(), lock: null, dx: 0, target: e.target, noSwipe: !!e.target.closest('.modal') || director.active };
});

window.addEventListener('pointermove', (e) => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  if (!drag.lock) {
    if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy) * 1.2) drag.lock = isWide() || drag.noSwipe ? 'none' : 'x';
    else if (Math.abs(dy) > 10) drag.lock = 'y';
  }
  if (drag.lock === 'x') {
    let d = dx;
    if ((ui.page === 0 && d > 0) || (ui.page === 2 && d < 0)) d *= 0.3; // rubber band
    drag.dx = d;
    track.classList.remove('animating');
    track.style.transform = `translate3d(calc(${-ui.page * 33.3333}% + ${d}px),0,0)`;
    world.setPanelProgress(ui.page - 1 - d / window.innerWidth);
  } else if (!drag.lock && ui.page === 1) {
    world.rex.lookAt((e.clientX / window.innerWidth) * 2 - 1);
  }
});

function endDrag(e) {
  if (!drag) return;
  const d = drag;
  drag = null;
  if (d.lock === 'x') {
    suppressClick = true;
    setTimeout(() => (suppressClick = false), 0);
    const v = d.dx / Math.max(1, performance.now() - d.t);
    const flick = Math.abs(v) > 0.45 || Math.abs(d.dx) > window.innerWidth * 0.2;
    // Swipe left (finger moves left) → Tasks; swipe right → Store.
    if (flick) { setPage(ui.page + (d.dx < 0 ? 1 : -1)); sfx.whoosh(); } else setPage(ui.page);
    return;
  }
  if (e.type === 'pointercancel' || d.lock) return;
  const tgt = d.target;
  const control = tgt.closest('button, input, label, select, [role=button]');
  if (control) {
    tapClickAt = performance.now();
    synthetic = true;
    try { control.click(); } finally { synthetic = false; }
    return;
  }
  if (director.active) return; // game taps go through #gameLayer
  // A tap: on the room → interact; on the empty strip beside a panel → go back.
  if (tgt.closest('.panel, .health-card, .profile, .dock, .banner, .modal')) return;
  if (ui.page === 1 || isWide()) handleTap(e.clientX, e.clientY);
  else setPage(1);
}
window.addEventListener('pointerup', endDrag);
// Stops iOS's double-tap recogniser (which swallows a quick second tap) and
// its late synthetic click; taps are already handled on pointerup.
window.addEventListener('touchend', (e) => { if (e.cancelable) e.preventDefault(); }, { passive: false });
window.addEventListener('pointercancel', endDrag);
document.addEventListener('click', (e) => {
  const dupe = !synthetic && performance.now() - tapClickAt < 800;
  if (suppressClick || dupe) { e.stopPropagation(); e.preventDefault(); }
}, true);

window.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowLeft') setPage(ui.page - 1);
  if (e.key === 'ArrowRight') setPage(ui.page + 1);
  if (director.active && (e.key === ' ' || e.key === 'ArrowUp')) { director.pointer(innerWidth / 2, innerHeight / 2); e.preventDefault(); return; }
  if (e.key === 'Escape') { $('#settings').hidden = true; director.closeMenu(); setPage(1); }
});

// ---------------------------------------------------------------- clicks

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-go],[data-act],[data-done],[data-claim],[data-tasktab],[data-storetab],[data-item],[data-buy],[data-cancel],[data-debug],[data-close],[data-game],[data-game-act],[data-close-games],#gamesBtn,#settingsBtn,#exitBtn');
  if (!el) return;
  unlockAudio();
  const ds = el.dataset;
  if (ds.go != null) { setPage(+ds.go); sfx.whoosh(); }
  else if (ds.act) doAction(ds.act);
  else if (ds.done) game.markDone(ds.done);
  else if (ds.claim) {
    const r = el.getBoundingClientRect();
    const t = game.state.tasks.find((x) => x.id === ds.claim);
    if (t) fx(`🪙+${t.coinReward}`, r.left + r.width / 2, r.top, 1, 0);
    game.claim(ds.claim);
  } else if (ds.tasktab) { ui.taskTab = ds.tasktab; sfx.tap(); renderTasks(); }
  else if (ds.storetab) { ui.storeTab = ds.storetab; ui.confirmId = null; sfx.tap(); renderStore(); }
  else if (ds.buy) {
    e.stopPropagation();
    const r = game.buy(ds.buy);
    ui.confirmId = null;
    if (!r.ok) {
      sfx.bad();
      toast(r.reason === 'coins' ? `You need ${r.need} more coins — finish a task! 📋` : 'Already yours!', 'bad');
    }
    renderStore();
  } else if (ds.cancel != null) { e.stopPropagation(); ui.confirmId = null; renderStore(); }
  else if (ds.item) {
    const item = STORE_ITEMS.find((i) => i.id === ds.item);
    const owned = item.kind !== 'consumable' && item.kind !== 'family' && game.state.owned[item.id];
    if (owned && item.id === 'hat') {
      const on = game.toggleWear('hat');
      sfx.tap();
      toast(on ? '🧢 Hat on!' : 'Hat off');
      return;
    }
    if (owned) { toast(`${item.name}: ${item.desc}`); return; }
    if (game.state.coins < item.cost) {
      sfx.bad();
      toast(`You need ${item.cost - game.state.coins} more coins. Finish a task! 📋`, 'bad');
      return;
    }
    ui.confirmId = ds.item;
    sfx.tap();
    renderStore();
  } else if (ds.debug) debug(ds.debug);
  else if (ds.close != null) $('#settings').hidden = true;
  else if (el.id === 'settingsBtn') openSettings();
  else if (el.id === 'exitBtn') bridge.post('close');
  else if (el.id === 'gamesBtn') director.openMenu();
  else if (ds.closeGames != null) director.closeMenu();
  else if (ds.game) director.choose(ds.game, ds.session);
  else if (ds.gameAct) director.act(ds.gameAct);
});

function debug(k) {
  if (k === 'coins') { game.state.coins += 200; game.changed(); }
  if (k === 'tasks') game.refillDemoTasks();
  if (k === 'sick') game.debugSick();
  if (k === 'fossil') game.debugFossil();
  if (k === 'reset') { game.reset(); $('#settings').hidden = true; }
}

function openSettings() {
  const s = game.state.settings;
  $('#setSound').checked = s.sound;
  $$('#setPixel button').forEach((b) => b.classList.toggle('on', +b.dataset.v === s.pixel));
  $$('#setSpeed button').forEach((b) => b.classList.toggle('on', +b.dataset.v === s.speed));
  $('#settings').hidden = false;
}
$('#settings').addEventListener('click', (e) => { if (e.target.id === 'settings') $('#settings').hidden = true; });
$('#gamesModal').addEventListener('click', (e) => { if (e.target.id === 'gamesModal') director.closeMenu(); });
$('#notice').addEventListener('click', () => hideNotice());
// Game input: taps go straight to the game (fast, for jumping) unless they
// land on a button.
$('#gameLayer').addEventListener('pointerdown', (e) => {
  unlockAudio();
  if (e.target.closest('button, [role=button]')) return;
  director.pointer(e.clientX, e.clientY);
});
$('#setSound').addEventListener('change', (e) => { game.setSetting('sound', e.target.checked); setSound(e.target.checked); });
$('#setPixel').addEventListener('click', (e) => {
  const v = +e.target.dataset.v; if (!v) return;
  game.setSetting('pixel', v); world.setPixel(v); openSettings();
});
$('#setSpeed').addEventListener('click', (e) => {
  const v = +e.target.dataset.v; if (!v) return;
  game.setSetting('speed', v); openSettings();
});

// ---------------------------------------------------------------- bridge

// Outgoing: WKWebView handler, Flutter webview JavaScriptChannel, or iframe parent.
const bridge = {
  post(type, data = {}) {
    const msg = { source: 'rex', type, ...data };
    try { window.webkit?.messageHandlers?.famotive?.postMessage(msg); } catch (_) { /* not embedded */ }
    try { window.FamotiveBridge?.postMessage(JSON.stringify(msg)); } catch (_) { /* not embedded */ }
    if (window.parent !== window) window.parent.postMessage(msg, '*');
  },
};
const director = new Director({ world, game, bridge, sfx, toast, embedded });
director.renderBadge();

// Incoming: the host app calls these.
window.RexGame = {
  setTasks: (list) => game.setTasks(list),
  approveTask: (id) => game.approve(String(id)),
  setCoins: (n) => { game.state.coins = n; game.changed(); },
  setName: (n) => { game.state.name = n; game.changed(); },
  // Safe-area padding (CSS px) from the host, e.g. the notch in landscape.
  setInsets: ({ top = 0, right = 0, bottom = 0, left = 0 } = {}) => {
    const st = document.documentElement.style;
    st.setProperty('--host-safe-t', top + 'px');
    st.setProperty('--host-safe-r', right + 'px');
    st.setProperty('--host-safe-b', bottom + 'px');
    st.setProperty('--host-safe-l', left + 'px');
  },
  getState: () => JSON.parse(JSON.stringify(game.state)),
  // Shared level: the child's real total XP.
  setPlayer: (p) => game.setPlayer(p),
  // { bonus: [{ sessionId, gameId, taskTitle, baseXp }], settings, enabled }
  setGames: (data) => director.setGames(data),
  launchGame: (payload) => director.launch(payload),
  gameResult: (data) => director.gameResult(data),
  chooseGame: (gameId, sessionId) => director.choose(gameId, sessionId),
};

if (initialInsets) window.RexGame.setInsets(initialInsets);

// ---------------------------------------------------------------- loop

let last = performance.now();
let tickAcc = 0;
let sneezeIn = 8;
let bubbleKey = '';

function updateBubble(now) {
  const s = game.state;
  const el = $('#bubble');
  let icon = '';
  if (now < ui.petUntil) icon = '❤️';
  else if (s.status === 'fossil') icon = '';
  else if (s.sleeping) icon = '💤';
  else if (s.status === 'sick') icon = '🤒';
  else {
    const low = game.lowestNeed;
    if (s.needs[low] < 40) icon = CARE[low].icon;
  }
  const visible = icon && (isWide() || ui.page === 1) && $('#settings').hidden;
  if (!visible) { el.hidden = true; bubbleKey = ''; return; }
  el.hidden = false;
  if (bubbleKey !== icon) {
    bubbleKey = icon;
    el.textContent = icon;
    el.classList.remove('pop'); void el.offsetWidth; el.classList.add('pop');
  }
  const p = world.rexHeadScreen();
  el.style.left = p.x + 'px';
  el.style.top = p.y + 'px';
}

function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  tickAcc += dt;
  if (tickAcc >= 1) { game.tick(tickAcc); tickAcc = 0; }

  const s = game.state;
  if (s.status === 'sick' && !s.sleeping && !world.rex.actionUntil) {
    sneezeIn -= dt;
    if (sneezeIn <= 0) {
      sneezeIn = 8 + Math.random() * 7;
      animate('sneeze', 1.1);
      setTimeout(() => { sfx.sneeze(); fxAtRex('🦠', 3, 90); }, 450);
    }
  }
  director.update(dt);
  world.update(dt, now / 1000);
  updateBubble(now);
  requestAnimationFrame(frame);
}

window.addEventListener('resize', () => { world.resize(); setPage(ui.page, false); });
wideMQ.addEventListener?.('change', () => setPage(1, false));

render();
setPage(1, false);
if (!game.state.seenHint) $('#swipeHint').hidden = false;
requestAnimationFrame(frame);
bridge.post('ready');


// ?debug=1 shows an input-event log (handy when testing inside WebViews).
if (params.get('debug') === '1') {
  const log = document.createElement('pre');
  log.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:99;background:rgba(0,0,0,.75);color:#0f0;font-size:11px;margin:0;padding:4px;pointer-events:none;max-height:200px;overflow:hidden';
  document.body.append(log);
  const add = (m) => { log.textContent = (m + '\n' + log.textContent).slice(0, 1500); };
  for (const t of ['pointerdown', 'pointerup', 'pointercancel', 'click'])
    window.addEventListener(t, (e) => add(`${t} ${e.target.className || e.target.tagName} ${e.isTrusted ? '' : '(synthetic)'}`), true);
  window.addEventListener('error', (e) => add('ERR ' + e.message));
}
