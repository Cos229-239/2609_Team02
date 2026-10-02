/**
 * `deleteAccount` callable: in-app account deletion (App Store guideline
 * 5.1.1(v); also what famotive.org/delete-my-data.html promises).
 *
 * data: { childId?: string, dryRun?: boolean }
 * - No childId: deletes the caller's own account.
 * - childId: an admin parent deletes one of their children's accounts.
 * - dryRun: returns what would happen (shown on the confirm screen) and
 *   changes nothing.
 *
 * The real run requires the caller to have signed in within the last
 * RECENT_LOGIN_SECONDS (the app re-authenticates first). Rules decided in
 * ./plan.ts. Runs with admin privileges, so Firestore rules don't apply.
 */
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, type DocumentReference } from 'firebase-admin/firestore';

import { planAccountDeletion, summarize, type HouseholdInfo, type MemberInfo } from './plan';

const RECENT_LOGIN_SECONDS = 5 * 60;

function toHousehold(id: string, d: FirebaseFirestore.DocumentData | undefined): HouseholdInfo {
  const ids = Array.isArray(d?.memberIds) ? d!.memberIds.filter((x: unknown): x is string => typeof x === 'string') : [];
  return { id, name: typeof d?.name === 'string' ? d.name : 'your household', ownerId: d?.ownerId ?? null, memberIds: ids };
}

async function householdsOf(uid: string): Promise<HouseholdInfo[]> {
  const snap = await getFirestore().collection('households').where('memberIds', 'array-contains', uid).get();
  return snap.docs.map((d) => toHousehold(d.id, d.data()));
}

async function deleteQuery(query: FirebaseFirestore.Query): Promise<number> {
  const snap = await query.get();
  const db = getFirestore();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    snap.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return snap.size;
}

/** Removes [uid] from a household it's only leaving, plus a child's own data there. */
async function leaveHousehold(ref: DocumentReference, uid: string, isChild: boolean): Promise<void> {
  if (isChild) {
    await deleteQuery(ref.collection('tasks').where('assignedToUserId', '==', uid));
    await deleteQuery(ref.collection('redemptions').where('childId', '==', uid));
    await deleteQuery(ref.collection('taskSchedules').where('assignedToUserId', '==', uid));
  }
  await ref.update({ memberIds: FieldValue.arrayRemove(uid) });
}

/** Deletes one user's profile, its subcollections, open join requests and login. */
async function deleteUser(uid: string): Promise<void> {
  const db = getFirestore();
  const userRef = db.collection('users').doc(uid);
  const pending = (await userRef.get()).data()?.pendingHouseholdIds;
  if (Array.isArray(pending)) {
    await Promise.all(
      pending
        .filter((id): id is string => typeof id === 'string')
        .map((id) => db.collection('households').doc(id).collection('joinRequests').doc(uid).delete()),
    );
  }
  await db.recursiveDelete(userRef); // includes fcmTokens
  try {
    await getAuth().deleteUser(uid);
  } catch (err) {
    if ((err as { code?: string }).code !== 'auth/user-not-found') throw err;
  }
}

// `invoker: 'public'` lets the app reach the Cloud Run service at all;
// Firebase Auth is still checked below (request.auth). Without it, a deploy
// that couldn't set the IAM policy makes every call fail with UNAUTHENTICATED.
export const deleteAccount = onCall({ invoker: 'public' }, async (request) => {
  const actorId = request.auth?.uid;
  if (!actorId) throw new HttpsError('unauthenticated', 'Sign in first.');
  const childId = typeof request.data?.childId === 'string' && request.data.childId ? request.data.childId : null;
  const dryRun = request.data?.dryRun === true;
  const targetId = childId ?? actorId;

  const db = getFirestore();

  // Load the target's households, everyone in them, and those people's households.
  const targetHouseholds = await householdsOf(targetId);
  const peopleIds = new Set<string>([actorId, targetId, ...targetHouseholds.flatMap((h) => h.memberIds)]);
  const profiles = await Promise.all([...peopleIds].map((id) => db.collection('users').doc(id).get()));
  const members = new Map<string, MemberInfo>();
  for (const p of profiles) {
    if (!p.exists) continue;
    const d = p.data()!;
    members.set(p.id, { id: p.id, name: d.name ?? '', role: d.role ?? '', createdByParentId: d.createdByParentId ?? null });
  }
  const householdsByUser = new Map<string, HouseholdInfo[]>([[targetId, targetHouseholds]]);
  // Only children the target created can be swept up, so only they need a lookup.
  for (const m of members.values()) {
    if (m.id !== targetId && m.role === 'child' && m.createdByParentId === targetId) {
      householdsByUser.set(m.id, await householdsOf(m.id));
    }
  }

  const plan = planAccountDeletion({ actorId, targetId, members, householdsByUser });
  const summary = summarize(plan, members);
  if (dryRun) return { ...summary, deleted: false };

  if (plan.forbidden) throw new HttpsError('permission-denied', plan.forbidden);
  if (plan.blockers.length) throw new HttpsError('failed-precondition', plan.blockers.join(' '));

  const authTime = Number(request.auth?.token.auth_time ?? 0);
  if (Date.now() / 1000 - authTime > RECENT_LOGIN_SECONDS) {
    throw new HttpsError('failed-precondition', 'Please confirm it\'s you again, then retry.', { reason: 'requires-recent-login' });
  }

  const targetIsChild = members.get(targetId)?.role === 'child';
  for (const h of plan.leaveHouseholds) {
    await leaveHousehold(db.collection('households').doc(h.id), targetId, targetIsChild);
  }
  for (const h of plan.deleteHouseholds) {
    await db.recursiveDelete(db.collection('households').doc(h.id));
  }
  for (const uid of plan.deleteUserIds) {
    await deleteUser(uid);
  }

  logger.info('Account deleted', {
    actorId,
    targetId,
    deletedHouseholds: plan.deleteHouseholds.map((h) => h.id),
    leftHouseholds: plan.leaveHouseholds.map((h) => h.id),
    deletedUsers: plan.deleteUserIds,
  });
  return { ...summary, deleted: true };
});
