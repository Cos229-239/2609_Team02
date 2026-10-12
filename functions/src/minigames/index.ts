/**
 * Mini-game bonus XP (the only place it is paid).
 *
 * The child's app moves `households/{h}/miniGameSessions/{taskId}` to
 * `finished` with its outcome (Firestore rules stamp `startedAt`/`finishedAt`
 * with the server time). This trigger then, in one transaction:
 * re-reads the session and its task, validates the outcome against the
 * session's settings snapshot and the measured play time (./plan.ts),
 * creates `xpTransactions/minigame_{taskId}` (create() fails if it already
 * exists → at most once), adds the bonus to the child's XP and marks the
 * session `rewarded` — or `rejected` with a reason, paying nothing.
 *
 * Runs with admin privileges; clients can't write any of the reward fields.
 */
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';

import { planAward } from './plan';

const SESSION_PATH = 'households/{householdId}/miniGameSessions/{sessionId}';

const millis = (v: unknown): number | null => (v instanceof Timestamp ? v.toMillis() : null);

export const awardMiniGameBonus = onDocumentUpdated(SESSION_PATH, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (after.status !== 'finished' || before.status === 'finished') return;

  const db = getFirestore();
  const { householdId, sessionId } = event.params;
  const householdRef = db.collection('households').doc(householdId);
  const sessionRef = householdRef.collection('miniGameSessions').doc(sessionId);

  const result = await db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    const session = sessionSnap.data();
    if (!session || session.status !== 'finished') return 'not finished';

    const taskId = typeof session.taskId === 'string' && session.taskId ? session.taskId : sessionId;
    // Keyed by the task, not the session: one bonus per approved task even
    // if more than one session ever pointed at it.
    const xpRef = householdRef.collection('xpTransactions').doc(`minigame_${taskId}`);
    const taskSnap = await tx.get(householdRef.collection('tasks').doc(taskId));
    const xpSnap = await tx.get(xpRef);
    if (xpSnap.exists) {
      // Already paid (a redelivered event after a partial failure): just settle the session.
      tx.update(sessionRef, { status: 'rewarded' });
      return 'already paid';
    }

    const task = taskSnap.data();
    const decision = planAward(
      {
        status: session.status,
        childId: session.childId,
        gameId: session.gameId,
        settings: session.settings,
        outcome: session.outcome,
        startedAtMs: millis(session.startedAt),
        finishedAtMs: millis(session.finishedAt),
        expiresAtMs: millis(session.expiresAt),
      },
      {
        exists: taskSnap.exists,
        status: task?.status,
        assignedToUserId: task?.assignedToUserId,
        rewardXp: task?.rewardXp,
      },
    );

    if (decision.action === 'ignore') return 'ignored';
    if (decision.action === 'reject') {
      tx.update(sessionRef, { status: 'rejected', rejectReason: decision.reason, rewardedAt: null });
      return `rejected: ${decision.reason}`;
    }

    const now = FieldValue.serverTimestamp();
    tx.create(xpRef, {
      childId: decision.childId,
      source: 'miniGame',
      sessionId,
      taskId,
      gameId: decision.gameId,
      baseXp: decision.baseXp,
      performance: decision.performance,
      multiplierPct: decision.multiplierPct,
      bonusXp: decision.bonusXp,
      finalXp: decision.finalXp,
      createdAt: now,
    });
    if (decision.bonusXp > 0) {
      tx.update(db.collection('users').doc(decision.childId), { xp: FieldValue.increment(decision.bonusXp) });
    }
    tx.update(sessionRef, {
      status: 'rewarded',
      baseXp: decision.baseXp,
      performance: decision.performance,
      multiplierPct: decision.multiplierPct,
      bonusXp: decision.bonusXp,
      finalXp: decision.finalXp,
      rewardedAt: now,
    });
    return `rewarded +${decision.bonusXp}`;
  });

  logger.info('Mini-game session settled', { householdId, sessionId, result });
});
