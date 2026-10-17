// Tiny chiptune sound effects (WebAudio, no assets).
let ctx = null;
let enabled = true;

export function setSound(on) { enabled = on; }

export function unlockAudio() {
  if (ctx) return;
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
  } catch (_) { ctx = null; }
}

function tone(freq, dur, { type = 'square', vol = 0.08, at = 0, slide = 0 } = {}) {
  if (!ctx || !enabled) return;
  const t = ctx.currentTime + at;
  const o = ctx.createOscillator();
  const g = ctx.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ctx.destination);
  o.start(t);
  o.stop(t + dur + 0.02);
}

function noise(dur, vol = 0.08, at = 0) {
  if (!ctx || !enabled) return;
  const len = Math.floor(ctx.sampleRate * dur);
  const buf = ctx.createBuffer(1, len, ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
  const src = ctx.createBufferSource();
  const g = ctx.createGain();
  g.gain.value = vol;
  src.buffer = buf;
  src.connect(g).connect(ctx.destination);
  src.start(ctx.currentTime + at);
}

export const sfx = {
  tap: () => tone(660, 0.05, { vol: 0.04 }),
  coin: () => { tone(988, 0.08); tone(1319, 0.18, { at: 0.08 }); },
  chomp: () => { noise(0.06, 0.1); noise(0.06, 0.1, 0.18); noise(0.06, 0.1, 0.36); },
  happy: () => { tone(523, 0.08, { type: 'triangle', vol: 0.12 }); tone(659, 0.08, { type: 'triangle', vol: 0.12, at: 0.09 }); tone(784, 0.16, { type: 'triangle', vol: 0.12, at: 0.18 }); },
  roar: () => tone(220, 0.35, { type: 'sawtooth', vol: 0.06, slide: -120 }),
  splash: () => { noise(0.4, 0.06); tone(880, 0.2, { type: 'sine', slide: 600, vol: 0.05, at: 0.1 }); },
  sneeze: () => { tone(500, 0.15, { type: 'triangle', slide: 300, vol: 0.06 }); noise(0.2, 0.12, 0.18); },
  bad: () => tone(200, 0.2, { slide: -60, vol: 0.06 }),
  levelUp: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.14, { at: i * 0.1, vol: 0.09 })),
  dig: () => { noise(0.08, 0.15); tone(140, 0.1, { at: 0.02, vol: 0.08 }); },
  revive: () => [392, 523, 659, 784, 1047, 1319].forEach((f, i) => tone(f, 0.16, { at: i * 0.08, type: 'triangle', vol: 0.1 })),
  whoosh: () => noise(0.12, 0.03),
  // Minigames
  note: (i) => tone([392, 523, 659, 784][i % 4], 0.28, { type: 'triangle', vol: 0.12 }),
  pop: () => { noise(0.07, 0.14); tone(900, 0.06, { slide: -500, vol: 0.05 }); },
  flip: () => tone(520, 0.05, { type: 'triangle', vol: 0.06, slide: 200 }),
  jump: () => tone(330, 0.16, { type: 'square', vol: 0.05, slide: 420 }),
  hit: () => { noise(0.15, 0.12); tone(160, 0.2, { slide: -80, vol: 0.07 }); },
  star: () => { tone(1175, 0.06, { vol: 0.05 }); tone(1568, 0.1, { vol: 0.05, at: 0.05 }); },
  win: () => [523, 659, 784, 1047, 784, 1047].forEach((f, i) => tone(f, 0.14, { at: i * 0.09, type: 'triangle', vol: 0.1 })),
  lose: () => [392, 330, 262].forEach((f, i) => tone(f, 0.22, { at: i * 0.16, type: 'triangle', vol: 0.09 })),
  tick: () => tone(1200, 0.03, { vol: 0.03 }),
  iris: () => tone(600, 0.35, { type: 'sine', slide: -450, vol: 0.06 }),
};
