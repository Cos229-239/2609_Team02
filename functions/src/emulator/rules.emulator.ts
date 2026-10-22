/**
 * Firestore security rules for the Family Goal / mini-game collections,
 * run against the emulator (see "npm run test:emulator").
 */
import { after, before, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteField,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const H = 'households/h1';
let env: RulesTestEnvironment;

const parent = () => env.authenticatedContext('parent').firestore();
const kid = () => env.authenticatedContext('kid').firestore();
const sibling = () => env.authenticatedContext('kid2').firestore();
const outsider = () => env.authenticatedContext('stranger').firestore();

const milestone = (extra: Record<string, unknown> = {}) => ({
  title: 'Park day',
  rewardTitle: 'Amusement park',
  boardLength: 20,
  spacesPerTask: 1,
  position: 0,
  status: 'active',
  startsAt: Timestamp.fromDate(new Date('2026-10-01')),
  endsAt: Timestamp.fromDate(new Date('2099-10-15')),
  ...extra,
});

const offered = (extra: Record<string, unknown> = {}) => ({
  childId: 'kid',
  taskId: 't1',
  gameId: 'balloonPopper',
  seed: 1,
  baseXp: 20,
  settings: {},
  status: 'offered',
  attempts: 0,
  createdAt: Timestamp.now(),
  expiresAt: Timestamp.fromMillis(Date.now() + 3 * 864e5),
  startedAt: null,
  finishedAt: null,
  outcome: null,
  ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-famotive-rules',
    firestore: { rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8') },
  });
});

after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, H), { name: 'Test', ownerId: 'parent', memberIds: ['parent', 'kid', 'kid2'] });
    await setDoc(doc(db, 'households/h2'), { name: 'Other', ownerId: 'stranger', memberIds: ['stranger'] });
    await setDoc(doc(db, 'users/parent'), { name: 'Pat', role: 'parent', householdId: 'h1', xp: 0, coins: 0 });
    await setDoc(doc(db, 'users/kid'), { name: 'Ava', role: 'child', householdId: 'h1', xp: 100, coins: 50 });
    await setDoc(doc(db, 'users/kid2'), { name: 'Bo', role: 'child', householdId: 'h1', xp: 0, coins: 0 });
    await setDoc(doc(db, 'users/stranger'), { name: 'X', role: 'parent', householdId: 'h2', xp: 0, coins: 0 });
    await setDoc(doc(db, `${H}/milestones/m1`), milestone());
    await setDoc(doc(db, `${H}/miniGameSessions/t1`), offered());
    await setDoc(doc(db, `${H}/progressEvents/t1`), { childId: 'kid', taskTitle: 'Dishes', presentedAt: null });
  });
});

// --- XP / coins -------------------------------------------------------------------

test('a child cannot raise their own XP or coins, but can spend coins', async () => {
  await assertFails(updateDoc(doc(kid(), 'users/kid'), { xp: 10_000 }));
  await assertFails(updateDoc(doc(kid(), 'users/kid'), { coins: 51 }));
  await assertSucceeds(updateDoc(doc(kid(), 'users/kid'), { coins: 40 }));
  await assertSucceeds(updateDoc(doc(kid(), 'users/kid'), { avatarEmoji: '🦄' }));
  // A parent's approval still pays XP/coins.
  await assertSucceeds(updateDoc(doc(parent(), 'users/kid'), { xp: 120, coins: 60 }));
});

test("a child can't change their own name, age or email; a parent can change name and age", async () => {
  await assertFails(updateDoc(doc(kid(), 'users/kid'), { name: 'Ava B.' }));
  await assertFails(updateDoc(doc(kid(), 'users/kid'), { age: 12 }));
  await assertFails(updateDoc(doc(kid(), 'users/kid'), { email: 'ava@example.com' }));
  await assertSucceeds(updateDoc(doc(parent(), 'users/kid'), { name: 'Ava B.', age: 9 }));
  await assertFails(updateDoc(doc(parent(), 'users/kid'), { email: 'ava@example.com' }));
  // Parents still edit their own profile.
  await assertSucceeds(updateDoc(doc(parent(), 'users/parent'), { name: 'Patricia', age: 40 }));
});

test('new profiles start with no XP or coins', async () => {
  const fresh = env.authenticatedContext('newbie').firestore();
  await assertFails(setDoc(doc(fresh, 'users/newbie'), { name: 'N', role: 'child', xp: 500 }));
  await assertSucceeds(setDoc(doc(fresh, 'users/newbie'), { name: 'N', role: 'child', xp: 0, coins: 0 }));
});

// --- Milestones ---------------------------------------------------------------------

test('only parents create and edit family goals, within valid bounds', async () => {
  await assertFails(setDoc(doc(kid(), `${H}/milestones/m2`), milestone()));
  await assertFails(updateDoc(doc(kid(), `${H}/milestones/m1`), { position: 20 }));
  await assertSucceeds(setDoc(doc(parent(), `${H}/milestones/m2`), milestone()));
  await assertFails(setDoc(doc(parent(), `${H}/milestones/m3`), milestone({ boardLength: 500 })));
  await assertFails(updateDoc(doc(parent(), `${H}/milestones/m1`), { position: 21 }));
  await assertSucceeds(updateDoc(doc(parent(), `${H}/milestones/m1`), { position: 1 }));
});

test('another household cannot read or change our goal', async () => {
  await assertFails(getDoc(doc(outsider(), `${H}/milestones/m1`)));
  await assertFails(updateDoc(doc(outsider(), `${H}/milestones/m1`), { position: 5 }));
  await assertSucceeds(getDoc(doc(kid(), `${H}/milestones/m1`)));
});

test('contributions are a create-only audit trail written by parents', async () => {
  const ref = `${H}/milestones/m1/contributions/t1`;
  await assertFails(setDoc(doc(kid(), ref), { childId: 'kid', spaces: 1 }));
  await assertSucceeds(setDoc(doc(parent(), ref), { childId: 'kid', spaces: 1 }));
  await assertFails(updateDoc(doc(parent(), ref), { spaces: 3 }));
});

test('a child may only mark their own progress event as shown', async () => {
  const ref = `${H}/progressEvents/t1`;
  await assertFails(updateDoc(doc(sibling(), ref), { presentedAt: Timestamp.now() }));
  await assertFails(updateDoc(doc(kid(), ref), { presentedAt: Timestamp.now(), taskTitle: 'x' }));
  await assertSucceeds(updateDoc(doc(kid(), ref), { presentedAt: Timestamp.now() }));
  await assertFails(setDoc(doc(kid(), `${H}/progressEvents/t9`), { childId: 'kid', presentedAt: null }));
});

// --- Mini-game sessions -----------------------------------------------------------------

test('parents offer sessions but can never pre-fill rewards', async () => {
  await assertSucceeds(setDoc(doc(parent(), `${H}/miniGameSessions/t2`), offered({ taskId: 't2' })));
  await assertFails(setDoc(doc(parent(), `${H}/miniGameSessions/t3`), offered({ bonusXp: 999 })));
  await assertFails(setDoc(doc(kid(), `${H}/miniGameSessions/t4`), offered()));
});

test('a child starts (server-stamped, at most twice), finishes and cannot write rewards', async () => {
  const ref = doc(kid(), `${H}/miniGameSessions/t1`);
  await assertFails(updateDoc(ref, { status: 'started', attempts: 1, startedAt: Timestamp.fromMillis(0) }));
  await assertFails(updateDoc(ref, { status: 'started', attempts: 2, startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { status: 'started', attempts: 1, startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { status: 'started', attempts: 2, startedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { status: 'started', attempts: 3, startedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { status: 'rewarded', bonusXp: 500 }));
  await assertFails(
    updateDoc(ref, { status: 'finished', outcome: { details: {} }, finishedAt: serverTimestamp(), bonusXp: 1 }),
  );
  await assertSucceeds(updateDoc(ref, { status: 'finished', outcome: { details: { popped: 3, target: 15 } }, finishedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { status: 'started', attempts: 3, startedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { outcome: { details: { popped: 15, target: 15 } } }));
});

test('siblings cannot play your bonus game; expired games cannot start; skipping is allowed', async () => {
  await assertFails(updateDoc(doc(sibling(), `${H}/miniGameSessions/t1`), { status: 'started', attempts: 1, startedAt: serverTimestamp() }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `${H}/miniGameSessions/old`), offered({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }));
  });
  await assertFails(updateDoc(doc(kid(), `${H}/miniGameSessions/old`), { status: 'started', attempts: 1, startedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(kid(), `${H}/miniGameSessions/t1`), { status: 'skipped' }));
  await assertFails(updateDoc(doc(kid(), `${H}/miniGameSessions/t1`), { status: 'started', attempts: 1, startedAt: serverTimestamp() }));
});

test('the XP ledger is server-only; settings are parent-only', async () => {
  await assertFails(setDoc(doc(kid(), `${H}/xpTransactions/minigame_t1`), { bonusXp: 100 }));
  await assertFails(setDoc(doc(parent(), `${H}/xpTransactions/minigame_t1`), { bonusXp: 100 }));
  await assertSucceeds(getDoc(doc(kid(), `${H}/xpTransactions/minigame_t1`)));
  await assertFails(setDoc(doc(kid(), `${H}/miniGameSettings/kid`), { multiplier: { maxPct: 300 } }));
  await assertSucceeds(setDoc(doc(parent(), `${H}/miniGameSettings/kid`), { multiplier: { maxPct: 300 } }));
  await assertSucceeds(updateDoc(doc(parent(), `${H}/miniGameSettings/kid`), { multiplier: deleteField() }));
  await assertFails(getDoc(doc(outsider(), `${H}/miniGameSettings/kid`)));
});

test("a parent's whole approval commit (task, XP, board, audit, event, bonus offer) passes the rules", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `${H}/tasks/t5`), { title: 'Dishes', assignedToUserId: 'kid', status: 'completed', rewardXp: 20 });
  });
  const db = parent();
  for (const path of [`${H}/miniGameSettings/household`, `${H}/miniGameSettings/kid`, `${H}/miniGameSessions/t5`, `${H}/progressEvents/t5`, `${H}/milestones/m1/contributions/t5`]) {
    await assertSucceeds(getDoc(doc(db, path)));
  }
  const batch = writeBatch(db);
  batch.update(doc(db, `${H}/tasks/t5`), { status: 'approved', approvedAt: Timestamp.now() });
  batch.update(doc(db, 'users/kid'), { xp: 120, coins: 55 });
  batch.set(doc(db, `${H}/milestones/m1/contributions/t5`), { childId: 'kid', spaces: 1, fromPosition: 0, toPosition: 1 });
  batch.update(doc(db, `${H}/milestones/m1`), { position: 1 });
  batch.set(doc(db, `${H}/miniGameSessions/t5`), offered({ taskId: 't5' }));
  batch.set(doc(db, `${H}/progressEvents/t5`), { childId: 'kid', taskTitle: 'Dishes', presentedAt: null, miniGameSessionId: 't5' });
  await assertSucceeds(batch.commit());
});
