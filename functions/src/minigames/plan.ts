/**
 * Pure mini-game bonus rules: outcome validation, performance, XP multiplier.
 * No Firebase imports, so it's unit tested with `node --test` (plan.test.ts).
 *
 * Mirrors lib/core/models/mini_game.dart, mini_game_settings.dart and
 * lib/core/services/xp_multiplier.dart. The app only shows a preview; this is
 * the authority that decides what's paid.
 * See Documents/Family_Milestones_and_MiniGames.md, section 5.
 */

export type GameId = 'balloonPopper' | 'matchPairs' | 'jumpAndRun' | 'memoryRun';
export const GAME_IDS: readonly GameId[] = ['balloonPopper', 'matchPairs', 'jumpAndRun', 'memoryRun'];

/** No setting can leave these bounds (percent; 100 = 1.0×). */
export const HARD_MIN_PCT = 100;
export const HARD_MAX_PCT = 300;
/** Same default as AppConstants.defaultTaskXp for tasks without rewardXp. */
export const DEFAULT_TASK_XP = 50;
/** Memory Run sequences never exceed this. */
export const MAX_SEQUENCE_LENGTH = 25;

type Raw = Record<string, unknown>;
const asMap = (v: unknown): Raw => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Raw) : {});

/** Same as Dart IntRange.read: numbers are rounded and clamped, anything else → fallback. */
export function readInt(raw: unknown, min: number, max: number, fallback: number): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return fallback;
  return Math.min(max, Math.max(min, Math.round(raw)));
}

const isCount = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;

// --- Settings (snapshotted on the session when it was offered) -------------------

export type Curve = 'gentle' | 'balanced' | 'challenging';
const CURVE_EXPONENT: Record<Curve, number> = { gentle: 0.7, balanced: 1.0, challenging: 1.5 };

export interface MultiplierSettings {
  minPct: number;
  maxPct: number;
  curve: Curve;
}

export function readMultiplier(raw: unknown): MultiplierSettings {
  const m = asMap(raw);
  const minPct = readInt(m.minPct, HARD_MIN_PCT, 150, 100);
  const maxPct = readInt(m.maxPct, minPct, HARD_MAX_PCT, Math.max(200, minPct));
  const curve = (['gentle', 'balanced', 'challenging'] as const).find((c) => c === m.curve) ?? 'balanced';
  return { minPct, maxPct, curve };
}

export function balloonSettings(raw: unknown) {
  const m = asMap(raw);
  return { targetCount: readInt(m.targetCount, 5, 40, 15), timeLimitSec: readInt(m.timeLimitSec, 15, 90, 30) };
}

export function matchPairsSettings(raw: unknown) {
  const m = asMap(raw);
  return { pairs: readInt(m.pairs, 3, 10, 6), maxMisses: readInt(m.maxMisses, 1, 10, 3) };
}

export const METERS_PER_SECOND = 10;

export function jumpAndRunSettings(raw: unknown) {
  const m = asMap(raw);
  const durationSec = readInt(m.durationSec, 15, 90, 30);
  const collectibleFrequency = readInt(m.collectibleFrequency, 1, 3, 2);
  return {
    durationSec,
    obstacleDensity: readInt(m.obstacleDensity, 1, 3, 2),
    collectibleFrequency,
    runLength: durationSec * METERS_PER_SECOND,
    collectibleCount: Math.min(60, Math.max(2, Math.floor((durationSec * collectibleFrequency) / 5))),
  };
}

export function memoryRunSettings(raw: unknown) {
  const m = asMap(raw);
  const speed = readInt(m.speed, 1, 3, 2);
  return {
    targetLength: readInt(m.targetLength, 3, MAX_SEQUENCE_LENGTH, 8),
    speed,
    stepMs: speed === 1 ? 900 : speed === 3 ? 450 : 650,
  };
}

// --- Multiplier -------------------------------------------------------------------

export function multiplierPct(performance: number, s: MultiplierSettings): number {
  const p = Number.isFinite(performance) ? Math.min(1, Math.max(0, performance)) : 0;
  const min = Math.min(HARD_MAX_PCT, Math.max(HARD_MIN_PCT, s.minPct));
  const max = Math.min(HARD_MAX_PCT, Math.max(min, s.maxPct));
  const raw = min + (max - min) * Math.pow(p, CURVE_EXPONENT[s.curve]);
  const rounded = Math.round(raw / 5) * 5;
  return Math.min(max, Math.max(min, rounded));
}

/** baseXp × pct / 100, rounded half up (integer math, same as Dart). */
export function finalXp(baseXp: number, pct: number): number {
  if (!(baseXp > 0)) return 0;
  return Math.floor((Math.floor(baseXp) * pct + 50) / 100);
}

// --- Outcome validation --------------------------------------------------------------

export type Validation = { ok: true; performance: number } | { ok: false; reason: string };

const ratio = (part: number, whole: number) => (whole <= 0 ? 0 : Math.min(1, Math.max(0, part / whole)));

/**
 * Checks a reported outcome against the session's settings and the
 * server-measured play time, and returns the performance it's worth.
 * [elapsedMs] = finishedAt − startedAt, both stamped by Firestore.
 */
export function validateOutcome(gameId: GameId, settingsRaw: unknown, outcomeRaw: unknown, elapsedMs: number): Validation {
  const settings = asMap(settingsRaw);
  const d = asMap(asMap(outcomeRaw).details);
  const fail = (reason: string): Validation => ({ ok: false, reason });
  if (!Number.isFinite(elapsedMs) || elapsedMs < 0) return fail('missing play time');

  switch (gameId) {
    case 'balloonPopper': {
      const s = balloonSettings(settings[gameId]);
      const { popped, target } = d;
      if (!isCount(popped) || !isCount(target)) return fail('malformed balloon counts');
      if (target !== s.targetCount) return fail('target does not match settings');
      if (popped > target) return fail('more balloons than the target');
      if (elapsedMs < popped * 150) return fail('too fast');
      return { ok: true, performance: ratio(popped, target) };
    }
    case 'matchPairs': {
      const s = matchPairsSettings(settings[gameId]);
      const { matched, pairs, misses } = d;
      if (!isCount(matched) || !isCount(pairs) || !isCount(misses)) return fail('malformed pair counts');
      if (pairs !== s.pairs) return fail('pairs do not match settings');
      if (matched > pairs) return fail('more matches than pairs');
      if (misses > s.maxMisses) return fail('more misses than allowed');
      if (matched !== pairs && misses !== s.maxMisses) return fail('game did not end');
      if (elapsedMs < matched * 400 + misses * 800) return fail('too fast');
      return { ok: true, performance: ratio(matched, pairs) };
    }
    case 'jumpAndRun': {
      const s = jumpAndRunSettings(settings[gameId]);
      const { distance, runLength, collected, collectibles } = d;
      if (!isCount(distance) || !isCount(runLength) || !isCount(collected) || !isCount(collectibles)) {
        return fail('malformed run counts');
      }
      if (runLength !== s.runLength || collectibles !== s.collectibleCount) return fail('course does not match settings');
      if (distance > runLength || collected > collectibles) return fail('counts out of range');
      // The runner can't cover ground faster than the game's fixed speed.
      if (elapsedMs < (distance / METERS_PER_SECOND) * 1000 * 0.9) return fail('too fast');
      const c = collectibles <= 0 ? 1 : ratio(collected, collectibles);
      return { ok: true, performance: 0.7 * ratio(distance, runLength) + 0.3 * c };
    }
    case 'memoryRun': {
      const s = memoryRunSettings(settings[gameId]);
      const { reached, target } = d;
      if (!isCount(reached) || !isCount(target)) return fail('malformed sequence counts');
      if (target !== s.targetLength || target > MAX_SEQUENCE_LENGTH) return fail('target does not match settings');
      if (reached > target) return fail('longer than the target');
      // Every round k shows k steps before the child can answer.
      const demoMs = ((reached * (reached + 1)) / 2) * s.stepMs;
      if (elapsedMs < demoMs * 0.8) return fail('too fast');
      return { ok: true, performance: ratio(reached, target) };
    }
  }
}

// --- Award decision --------------------------------------------------------------------

export interface SessionData {
  status?: unknown;
  childId?: unknown;
  gameId?: unknown;
  settings?: unknown;
  outcome?: unknown;
  /** Milliseconds since epoch (server timestamps). */
  startedAtMs?: number | null;
  finishedAtMs?: number | null;
  expiresAtMs?: number | null;
}

export interface TaskInfo {
  exists: boolean;
  status?: unknown;
  assignedToUserId?: unknown;
  rewardXp?: unknown;
}

export type AwardDecision =
  | { action: 'ignore' }
  | { action: 'reject'; reason: string }
  | {
      action: 'reward';
      childId: string;
      gameId: GameId;
      baseXp: number;
      performance: number;
      multiplierPct: number;
      finalXp: number;
      bonusXp: number;
    };

/** Everything the award trigger decides, given the freshly read documents. */
export function planAward(session: SessionData, task: TaskInfo): AwardDecision {
  if (session.status !== 'finished') return { action: 'ignore' };
  const childId = session.childId;
  if (typeof childId !== 'string' || !childId) return { action: 'reject', reason: 'no child' };
  const gameId = GAME_IDS.find((g) => g === session.gameId);
  if (!gameId) return { action: 'reject', reason: 'unknown game' };
  const { startedAtMs, finishedAtMs, expiresAtMs } = session;
  if (typeof startedAtMs !== 'number' || typeof finishedAtMs !== 'number') return { action: 'reject', reason: 'not started' };
  if (typeof expiresAtMs === 'number' && finishedAtMs >= expiresAtMs) return { action: 'reject', reason: 'expired' };

  // Only the qualifying task's own XP, read from the task itself.
  if (!task.exists || task.status !== 'approved' || task.assignedToUserId !== childId) {
    return { action: 'reject', reason: 'task is not an approved task of this child' };
  }
  const baseXp = typeof task.rewardXp === 'number' && task.rewardXp >= 0 ? Math.floor(task.rewardXp) : DEFAULT_TASK_XP;

  const v = validateOutcome(gameId, session.settings, session.outcome, finishedAtMs - startedAtMs);
  if (!v.ok) return { action: 'reject', reason: v.reason };

  const pct = multiplierPct(v.performance, readMultiplier(asMap(session.settings).multiplier));
  const total = finalXp(baseXp, pct);
  return {
    action: 'reward',
    childId,
    gameId,
    baseXp,
    performance: v.performance,
    multiplierPct: pct,
    finalXp: total,
    bonusXp: total - baseXp,
  };
}
