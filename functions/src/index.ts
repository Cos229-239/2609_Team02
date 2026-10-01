/**
 * Famotive push notifications (Firebase Cloud Messaging).
 *
 * Children are notified when a task is created in the pool, assigned to
 * them, due today, past due, or approved. Parents are notified when a child
 * accepts (claims) a task, completes a task, or redeems a reward.
 *
 * Device tokens live at `users/{uid}/fcmTokens/{token}` (written by the
 * app's NotificationService). A user can opt out with
 * `users/{uid}.pushNotificationsEnabled = false` (Settings > Notifications).
 *
 * Which notifications to send is decided by the pure functions in
 * ./notifications/plan.ts; this file only does the Firestore/FCM I/O.
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  onDocumentCreatedWithAuthContext,
  onDocumentUpdatedWithAuthContext,
} from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, type DocumentData } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

import { buildMessage, type MessageContext } from './notifications/messages';
import {
  dueSweepWindow,
  planDueReminder,
  planRedemptionCreated,
  planTaskCreated,
  planTaskUpdated,
  type Audience,
  type DueNotificationLog,
  type NotificationKind,
  type PlannedNotification,
  type TaskData,
} from './notifications/plan';

initializeApp();
setGlobalOptions({ maxInstances: 10 });

const db = getFirestore();

const TASK_PATH = 'households/{householdId}/tasks/{taskId}';
const REDEMPTION_PATH = 'households/{householdId}/redemptions/{redemptionId}';

/** FCM error codes meaning "this token is dead — forget it". */
const STALE_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// --- Firestore helpers -------------------------------------------------------

interface UserDoc {
  name?: string;
  role?: string;
  householdId?: string | null;
  pushNotificationsEnabled?: boolean;
}

function toTaskData(data: DocumentData | undefined): TaskData {
  const d = data ?? {};
  const due = d.dueDate as Timestamp | null | undefined;
  return {
    title: d.title,
    assignedToUserId: d.assignedToUserId ?? null,
    status: d.status,
    archived: d.archived === true,
    dueDate: due && typeof due.toDate === 'function' ? due.toDate() : null,
    claimedBy: d.claimedBy ?? null,
  };
}

/** Small per-invocation cache so one event never reads a user twice. */
class UserCache {
  private readonly cache = new Map<string, Promise<UserDoc | null>>();

  get(uid: string | null | undefined): Promise<UserDoc | null> {
    if (!uid) return Promise.resolve(null);
    let p = this.cache.get(uid);
    if (!p) {
      p = db
        .collection('users')
        .doc(uid)
        .get()
        .then((s) => (s.exists ? (s.data() as UserDoc) : null));
      this.cache.set(uid, p);
    }
    return p;
  }
}

async function resolveRecipients(
  householdId: string,
  audience: Audience,
  excludeUserIds: string[],
  users: UserCache,
): Promise<string[]> {
  let ids: string[];

  if (audience.type === 'user') {
    const user = await users.get(audience.userId);
    // Only notify members of the household the change happened in.
    ids = user && user.householdId === householdId && user.pushNotificationsEnabled !== false
      ? [audience.userId]
      : [];
  } else {
    const role = audience.type === 'parents' ? 'parent' : 'child';
    const snap = await db
      .collection('users')
      .where('householdId', '==', householdId)
      .where('role', '==', role)
      .get();
    ids = snap.docs
      .filter((d) => (d.data() as UserDoc).pushNotificationsEnabled !== false)
      .map((d) => d.id);
  }

  return ids.filter((id) => !excludeUserIds.includes(id));
}

/** Sends one notification to every registered device of [userIds]. */
async function sendToUsers(
  userIds: string[],
  kind: NotificationKind,
  ctx: MessageContext,
  data: Record<string, string>,
): Promise<void> {
  if (userIds.length === 0) {
    logger.info('No recipients (opted out, not in household, or only the actor)', { kind });
    return;
  }

  const tokenDocs = (
    await Promise.all(userIds.map((uid) => db.collection('users').doc(uid).collection('fcmTokens').get()))
  ).flatMap((s) => s.docs);
  if (tokenDocs.length === 0) {
    logger.info('Recipients have no registered devices', { kind, userIds });
    return;
  }

  const { title, body } = buildMessage(kind, ctx);
  const payloadData = { ...data, type: kind };

  // sendEachForMulticast accepts at most 500 tokens per call.
  for (let i = 0; i < tokenDocs.length; i += 500) {
    const chunk = tokenDocs.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((d) => d.id),
      notification: { title, body },
      data: payloadData,
      android: { priority: 'high', notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    const stale: Promise<unknown>[] = [];
    res.responses.forEach((r, idx) => {
      if (r.success) return;
      const code = r.error?.code ?? '';
      if (STALE_TOKEN_CODES.has(code)) {
        stale.push(chunk[idx].ref.delete());
      } else {
        logger.warn('FCM send failed', { kind, code, message: r.error?.message });
      }
    });
    await Promise.all(stale);

    logger.info('Sent notification', {
      kind,
      users: userIds.length,
      success: res.successCount,
      failure: res.failureCount,
    });
  }
}

async function dispatch(
  plans: PlannedNotification[],
  householdId: string,
  ctx: MessageContext,
  data: Record<string, string>,
  users: UserCache,
): Promise<void> {
  for (const plan of plans) {
    const recipients = await resolveRecipients(householdId, plan.audience, plan.excludeUserIds, users);
    await sendToUsers(recipients, plan.kind, ctx, { ...data, householdId });
  }
}

async function taskContext(
  raw: DocumentData | undefined,
  actorId: string | undefined,
  users: UserCache,
): Promise<MessageContext> {
  const task = raw ?? {};
  const assigneeId = (task.assignedToUserId as string | null | undefined) ?? undefined;
  const [actor, assignee] = await Promise.all([users.get(actorId), users.get(assigneeId)]);
  return {
    taskTitle: task.title,
    rewardXp: task.rewardXp,
    coinReward: task.coinReward,
    actorName: actor?.name,
    // Parent-facing copy is about the child who owns the task.
    childName: assignee?.name ?? actor?.name,
  };
}

// --- Triggers ----------------------------------------------------------------

/** New task: "new quest available" (pool) or "new quest assigned". */
export const notifyOnTaskCreated = onDocumentCreatedWithAuthContext(TASK_PATH, async (event) => {
  const raw = event.data?.data();
  if (!raw) return;

  const plans = planTaskCreated(toTaskData(raw), event.authId);
  logger.info('Task created', { taskId: event.params.taskId, actor: event.authId, plans: plans.map((p) => p.kind) });
  if (plans.length === 0) return;

  const users = new UserCache();
  const ctx = await taskContext(raw, event.authId, users);
  await dispatch(plans, event.params.householdId, ctx, { taskId: event.params.taskId }, users);
});

/** Task changed: assigned / accepted / completed / approved. */
export const notifyOnTaskUpdated = onDocumentUpdatedWithAuthContext(TASK_PATH, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const plans = planTaskUpdated(toTaskData(before), toTaskData(after), event.authId);
  if (plans.length > 0) {
    logger.info('Task updated', { taskId: event.params.taskId, actor: event.authId, plans: plans.map((p) => p.kind) });
  }
  if (plans.length === 0) return;

  const users = new UserCache();
  const ctx = await taskContext(after, event.authId, users);
  await dispatch(plans, event.params.householdId, ctx, { taskId: event.params.taskId }, users);
});

/** Child redeemed a reward: tell the parents. */
export const notifyOnRewardRedeemed = onDocumentCreatedWithAuthContext(REDEMPTION_PATH, async (event) => {
  const raw = event.data?.data();
  if (!raw) return;

  const users = new UserCache();
  const child = await users.get(raw.childId as string | undefined);
  const ctx: MessageContext = {
    childName: child?.name,
    rewardTitle: raw.rewardTitle,
    rewardIcon: raw.rewardIcon,
    coinCost: raw.coinCost,
  };
  await dispatch(
    planRedemptionCreated(event.authId),
    event.params.householdId,
    ctx,
    { redemptionId: event.params.redemptionId },
    users,
  );
});

/**
 * Every 15 minutes: "due today" and "past due" reminders for assigned,
 * still-pending tasks. Each reminder is sent once per due date — recorded
 * in the task's `notificationLog` so editing the due date re-arms it.
 */
export const sendDueReminders = onSchedule({ schedule: 'every 15 minutes', timeZone: 'UTC' }, async () => {
  const now = new Date();
  const { from, to } = dueSweepWindow(now);

  const snap = await db
    .collectionGroup('tasks')
    .where('dueDate', '>=', Timestamp.fromDate(from))
    .where('dueDate', '<=', Timestamp.fromDate(to))
    .get();

  const users = new UserCache();
  for (const doc of snap.docs) {
    const raw = doc.data();
    const task = toTaskData(raw);
    const log = (raw.notificationLog ?? {}) as DueNotificationLog;
    const kind = planDueReminder(task, now, log);
    const householdId = doc.ref.parent.parent?.id;
    if (!kind || !householdId || !task.dueDate || !task.assignedToUserId) continue;

    try {
      const ctx = await taskContext(raw, undefined, users);
      await dispatch(
        [{ kind, audience: { type: 'user', userId: task.assignedToUserId }, excludeUserIds: [] }],
        householdId,
        ctx,
        { taskId: doc.id },
        users,
      );
      await doc.ref.update({
        [kind === 'task_due' ? 'notificationLog.dueFor' : 'notificationLog.overdueFor']: task.dueDate.getTime(),
      });
    } catch (err) {
      logger.error('Due reminder failed', { taskId: doc.id, householdId, err });
    }
  }
});
