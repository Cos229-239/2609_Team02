/**
 * `manageChildAccount` callable: a parent changes a child's password or
 * login email without the child (or the parent) leaving the app.
 *
 * data: { childId: string, password?: string, email?: string } (exactly
 * one of password / email). Who may do it: ./manage-plan.ts. Like
 * `deleteAccount`, the parent must have signed in within the last few
 * minutes (the app asks for their own password first).
 *
 * Changing the password signs the child out on their other devices
 * (Firebase revokes refresh tokens on a password change; we revoke
 * explicitly too).
 */
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { manageForbidden, parseChange } from './manage-plan';
import type { HouseholdInfo, MemberInfo } from './plan';

const RECENT_LOGIN_SECONDS = 5 * 60;

function toMember(snap: FirebaseFirestore.DocumentSnapshot): MemberInfo | undefined {
  if (!snap.exists) return undefined;
  const d = snap.data()!;
  return { id: snap.id, name: d.name ?? '', role: d.role ?? '', createdByParentId: d.createdByParentId ?? null };
}

export const manageChildAccount = onCall({ invoker: 'public' }, async (request) => {
  const actorId = request.auth?.uid;
  if (!actorId) throw new HttpsError('unauthenticated', 'Sign in first.');
  const childId = typeof request.data?.childId === 'string' ? request.data.childId : '';
  if (!childId) throw new HttpsError('invalid-argument', 'Which child?');
  const change = parseChange(request.data);
  if (typeof change === 'string') throw new HttpsError('invalid-argument', change);

  const db = getFirestore();
  const [actorSnap, childSnap, householdsSnap] = await Promise.all([
    db.collection('users').doc(actorId).get(),
    db.collection('users').doc(childId).get(),
    db.collection('households').where('memberIds', 'array-contains', childId).get(),
  ]);
  const childHouseholds: HouseholdInfo[] = householdsSnap.docs.map((h) => {
    const d = h.data();
    return {
      id: h.id,
      name: typeof d.name === 'string' ? d.name : '',
      ownerId: d.ownerId ?? null,
      memberIds: Array.isArray(d.memberIds) ? d.memberIds.filter((x: unknown): x is string => typeof x === 'string') : [],
    };
  });
  const forbidden = manageForbidden({ actor: toMember(actorSnap), child: toMember(childSnap), childHouseholds });
  if (forbidden) throw new HttpsError('permission-denied', forbidden);

  const authTime = Number(request.auth?.token.auth_time ?? 0);
  if (Date.now() / 1000 - authTime > RECENT_LOGIN_SECONDS) {
    throw new HttpsError('failed-precondition', 'Please confirm it\'s you again, then retry.', { reason: 'requires-recent-login' });
  }

  const auth = getAuth();
  try {
    if (change.kind === 'password') {
      await auth.updateUser(childId, { password: change.password });
      await auth.revokeRefreshTokens(childId);
    } else {
      await auth.updateUser(childId, { email: change.email, emailVerified: false });
      await childSnap.ref.update({ email: change.email });
    }
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'Another account already uses that email.');
    }
    if (code === 'auth/invalid-password') {
      throw new HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }
    if (code === 'auth/user-not-found') {
      throw new HttpsError('failed-precondition', 'That child account no longer has a login.');
    }
    logger.error('manageChildAccount failed', { actorId, childId, kind: change.kind, err });
    throw new HttpsError('internal', 'Something went wrong. Please try again.');
  }
  logger.info('Child login changed', { actorId, childId, kind: change.kind });
  return { ok: true, ...(change.kind === 'email' ? { email: change.email } : {}) };
});
