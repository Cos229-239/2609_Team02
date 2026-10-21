/**
 * The awardMiniGameBonus trigger against the Firestore + Functions
 * emulators (see "npm run test:emulator"): pays once, rejects bad outcomes,
 * and a replayed/retried finish never pays twice.
 */
import { before, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';

const H = 'households/award';
let db: Firestore;

const settings = {
  balloonPopper: { targetCount: 10, timeLimitSec: 30 },
  multiplier: { minPct: 100, maxPct: 200, curve: 'balanced' },
};

async function waitFor<T>(read: () => Promise<T>, done: (v: T) => boolean, ms = 20000): Promise<T> {
  const end = Date.now() + ms;
  let v = await read();
  while (!done(v) && Date.now() < end) {
    await new Promise((r) => setTimeout(r, 250));
    v = await read();
  }
  return v;
}

const xp = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('xp') as number;
const session = async (id: string) => (await db.doc(`${H}/miniGameSessions/${id}`).get()).data()!;

async function offer(id: string, extra: Record<string, unknown> = {}) {
  await db.doc(`${H}/tasks/${id}`).set({ title: id, assignedToUserId: 'kid', status: 'approved', rewardXp: 20 });
  await db.doc(`${H}/miniGameSessions/${id}`).set({
    childId: 'kid',
    taskId: id,
    gameId: 'balloonPopper',
    seed: 1,
    baseXp: 20,
    settings,
    status: 'started',
    attempts: 1,
    createdAt: Timestamp.now(),
    expiresAt: Timestamp.fromMillis(Date.now() + 864e5),
    startedAt: Timestamp.fromMillis(Date.now() - 30_000),
    ...extra,
  });
}

const finish = (id: string, popped: number, startedMsAgo = 30_000) =>
  db.doc(`${H}/miniGameSessions/${id}`).update({
    status: 'finished',
    outcome: { details: { popped, target: 10 }, completed: popped === 10, elapsedMs: startedMsAgo },
    finishedAt: Timestamp.now(),
  });

before(async () => {
  initializeApp({ projectId: 'demo-famotive' });
  db = getFirestore();
  await db.doc(H).set({ name: 'Award', memberIds: ['kid'] });
  await db.doc('users/kid').set({ name: 'Ava', role: 'child', xp: 20, coins: 0 });
});

test('a valid finished game pays the bonus exactly once', async () => {
  await offer('ok');
  await finish('ok', 5); // 50% → 1.5× → 30 XP total, +10 bonus
  const s = await waitFor(() => session('ok'), (v) => v.status !== 'finished');
  assert.equal(s.status, 'rewarded');
  assert.equal(s.multiplierPct, 150);
  assert.equal(s.bonusXp, 10);
  assert.equal(s.finalXp, 30);
  assert.equal(await xp('kid'), 30);
  const ledger = await db.doc(`${H}/xpTransactions/minigame_ok`).get();
  assert.equal(ledger.get('bonusXp'), 10);
  assert.equal(ledger.get('baseXp'), 20);

  // A replayed finish (retry / duplicate delivery / tampering) never pays again.
  await db.doc(`${H}/miniGameSessions/ok`).update({ status: 'started' });
  await finish('ok', 10);
  const again = await waitFor(() => session('ok'), (v) => v.status !== 'finished');
  assert.equal(again.status, 'rewarded');
  assert.equal(await xp('kid'), 30);
});

test('a second session pointing at an already-rewarded task pays nothing', async () => {
  const before = await xp('kid');
  await offer('dup', { taskId: 'ok' });
  await finish('dup', 10);
  const s = await waitFor(() => session('dup'), (v) => v.status !== 'finished');
  assert.equal(s.status, 'rewarded', 'settled against the existing ledger entry');
  assert.equal(s.bonusXp, undefined);
  assert.equal(await xp('kid'), before);
});

test('implausible outcomes are rejected and pay nothing', async () => {
  const before = await xp('kid');
  await offer('fast', { startedAt: Timestamp.now() });
  await finish('fast', 10, 0); // 10 balloons in ~0 s
  const s = await waitFor(() => session('fast'), (v) => v.status !== 'finished');
  assert.equal(s.status, 'rejected');
  assert.equal(s.rejectReason, 'too fast');

  await offer('cheat');
  await finish('cheat', 99);
  const c = await waitFor(() => session('cheat'), (v) => v.status !== 'finished');
  assert.equal(c.status, 'rejected');
  assert.equal(await xp('kid'), before);
  assert.equal((await db.doc(`${H}/xpTransactions/minigame_cheat`).get()).exists, false);
});

test('a session whose task is no longer approved for this child pays nothing', async () => {
  const before = await xp('kid');
  await offer('moved');
  await db.doc(`${H}/tasks/moved`).update({ status: 'pending' });
  await finish('moved', 10);
  const s = await waitFor(() => session('moved'), (v) => v.status !== 'finished');
  assert.equal(s.status, 'rejected');
  assert.equal(await xp('kid'), before);
});
