import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  finalXp,
  jumpAndRunSettings,
  multiplierPct,
  planAward,
  readMultiplier,
  validateOutcome,
  type SessionData,
  type TaskInfo,
} from './plan';

// Same table as test/xp_multiplier_test.dart: the app's preview and the
// server's award must agree.
const CASES: [number, string, number, number, number][] = [
  // performance, curve, minPct, maxPct, expected pct
  [0, 'balanced', 100, 200, 100],
  [1, 'balanced', 100, 200, 200],
  [0.5, 'balanced', 100, 200, 150],
  [0.33, 'balanced', 100, 200, 135],
  [0.5, 'gentle', 100, 200, 160],
  [0.5, 'challenging', 100, 200, 135],
  [0.8, 'balanced', 120, 300, 265],
  [2, 'balanced', 100, 200, 200],
  [-1, 'balanced', 100, 200, 100],
];

test('multiplier curve matches the shared table', () => {
  for (const [p, curve, minPct, maxPct, expected] of CASES) {
    assert.equal(multiplierPct(p, readMultiplier({ minPct, maxPct, curve })), expected, `${p} ${curve} ${minPct}-${maxPct}`);
  }
});

test('XP rounding: 20 XP at 1.5x is 30; half-up integer math', () => {
  assert.equal(finalXp(20, 150), 30);
  assert.equal(finalXp(15, 135), 20); // 20.25 → 20
  assert.equal(finalXp(10, 125), 13); // 12.5 → 13
  assert.equal(finalXp(50, 100), 50);
  assert.equal(finalXp(0, 300), 0);
});

test('multiplier settings are clamped to safe bounds', () => {
  assert.deepEqual(readMultiplier({ minPct: 50, maxPct: 900, curve: 'wild' }), { minPct: 100, maxPct: 300, curve: 'balanced' });
  assert.deepEqual(readMultiplier({ minPct: 150, maxPct: 120 }), { minPct: 150, maxPct: 150, curve: 'balanced' });
  assert.deepEqual(readMultiplier(undefined), { minPct: 100, maxPct: 200, curve: 'balanced' });
});

const settings = {
  balloonPopper: { targetCount: 15, timeLimitSec: 30 },
  matchPairs: { pairs: 6, maxMisses: 3 },
  jumpAndRun: { durationSec: 30, obstacleDensity: 2, collectibleFrequency: 2 },
  memoryRun: { targetLength: 8, speed: 2 },
  multiplier: { minPct: 100, maxPct: 200, curve: 'balanced' },
};

test('balloon popper: counts must fit the target and the clock', () => {
  assert.deepEqual(validateOutcome('balloonPopper', settings, { details: { popped: 15, target: 15 } }, 30000), {
    ok: true,
    performance: 1,
  });
  assert.equal(validateOutcome('balloonPopper', settings, { details: { popped: 16, target: 15 } }, 30000).ok, false);
  assert.equal(validateOutcome('balloonPopper', settings, { details: { popped: 5, target: 5 } }, 30000).ok, false);
  assert.equal(validateOutcome('balloonPopper', settings, { details: { popped: 15, target: 15 } }, 500).ok, false);
  assert.equal(validateOutcome('balloonPopper', settings, { details: { popped: 1.5, target: 15 } }, 30000).ok, false);
});

test('match pairs: three-miss limit and a real ending are enforced', () => {
  const ok = validateOutcome('matchPairs', settings, { details: { matched: 4, pairs: 6, misses: 3 } }, 20000);
  assert.deepEqual(ok, { ok: true, performance: 4 / 6 });
  assert.equal(validateOutcome('matchPairs', settings, { details: { matched: 6, pairs: 6, misses: 1 } }, 20000).ok, true);
  assert.equal(validateOutcome('matchPairs', settings, { details: { matched: 4, pairs: 6, misses: 4 } }, 20000).ok, false);
  assert.equal(validateOutcome('matchPairs', settings, { details: { matched: 4, pairs: 6, misses: 1 } }, 20000).ok, false);
  assert.equal(validateOutcome('matchPairs', settings, { details: { matched: 6, pairs: 6, misses: 0 } }, 1000).ok, false);
});

test('jump and run: course size comes from the settings, speed is capped', () => {
  const course = jumpAndRunSettings(settings.jumpAndRun);
  assert.equal(course.runLength, 300);
  assert.equal(course.collectibleCount, 12);
  const full = { details: { distance: 300, runLength: 300, collected: 6, collectibles: 12 } };
  const v = validateOutcome('jumpAndRun', settings, full, 30000);
  assert.equal(v.ok, true);
  assert.ok(v.ok && Math.abs(v.performance - 0.85) < 1e-9);
  assert.equal(validateOutcome('jumpAndRun', settings, full, 10000).ok, false);
  assert.equal(
    validateOutcome('jumpAndRun', settings, { details: { distance: 300, runLength: 300, collected: 3, collectibles: 3 } }, 30000).ok,
    false,
  );
});

test('memory run: up to 25 steps, never past the target, demo time respected', () => {
  assert.deepEqual(validateOutcome('memoryRun', settings, { details: { reached: 8, target: 8 } }, 60000), {
    ok: true,
    performance: 1,
  });
  assert.equal(validateOutcome('memoryRun', settings, { details: { reached: 9, target: 8 } }, 60000).ok, false);
  assert.equal(validateOutcome('memoryRun', settings, { details: { reached: 8, target: 8 } }, 5000).ok, false);
  const long = { ...settings, memoryRun: { targetLength: 99, speed: 3 } };
  assert.equal(validateOutcome('memoryRun', long, { details: { reached: 25, target: 25 } }, 200000).ok, true);
  assert.equal(validateOutcome('memoryRun', long, { details: { reached: 26, target: 26 } }, 200000).ok, false);
});

const finished = (overrides: Partial<SessionData> = {}): SessionData => ({
  status: 'finished',
  childId: 'kid',
  gameId: 'balloonPopper',
  settings,
  outcome: { details: { popped: 15, target: 15 } },
  startedAtMs: 1_000_000,
  finishedAtMs: 1_030_000,
  expiresAtMs: 9_000_000,
  ...overrides,
});
const approved: TaskInfo = { exists: true, status: 'approved', assignedToUserId: 'kid', rewardXp: 20 };

test('award: base XP from the task, multiplied once', () => {
  assert.deepEqual(planAward(finished(), approved), {
    action: 'reward',
    childId: 'kid',
    gameId: 'balloonPopper',
    baseXp: 20,
    performance: 1,
    multiplierPct: 200,
    finalXp: 40,
    bonusXp: 20,
  });
  const missingXp = planAward(finished(), { ...approved, rewardXp: undefined });
  assert.equal(missingXp.action === 'reward' && missingXp.baseXp, 50);
});

test('award: only finished sessions of approved tasks of the same child', () => {
  assert.deepEqual(planAward(finished({ status: 'started' }), approved), { action: 'ignore' });
  assert.deepEqual(planAward(finished({ status: 'rewarded' }), approved), { action: 'ignore' });
  assert.equal(planAward(finished(), { ...approved, status: 'completed' }).action, 'reject');
  assert.equal(planAward(finished(), { ...approved, assignedToUserId: 'sibling' }).action, 'reject');
  assert.equal(planAward(finished(), { exists: false }).action, 'reject');
  assert.equal(planAward(finished({ gameId: 'chess' }), approved).action, 'reject');
  assert.equal(planAward(finished({ startedAtMs: null }), approved).action, 'reject');
  assert.equal(planAward(finished({ finishedAtMs: 9_000_000 }), approved).action, 'reject');
});

test('award: a too-generous multiplier setting is still capped at 3x', () => {
  const greedy = finished({ settings: { ...settings, multiplier: { minPct: 100, maxPct: 1000 } } });
  const d = planAward(greedy, approved);
  assert.equal(d.action === 'reward' && d.multiplierPct, 300);
  assert.equal(d.action === 'reward' && d.finalXp, 60);
});
