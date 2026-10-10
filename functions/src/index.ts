/**
 * Famotive push notifications (Firebase Cloud Messaging).
 *
 * Children are notified when a task is created in the pool, assigned to
 * them, or approved, plus one 9 AM (household time) digest of what's due
 * today / overdue from yesterday. Parents are notified when a child accepts
 * (claims) a task, completes a task, or redeems a reward.
 *
 * Repeating tasks: parents create `households/{id}/taskSchedules/{id}`;
 * this file generates one ordinary task per occurrence (id
 * `{scheduleId}_{YYYYMMDD}`), a day ahead, so each is completed and approved
 * on its own. Calendar math lives in ./notifications/recurrence.ts.
 *
 * Households: membership is `households/{id}.memberIds` (a user can be in
 * several). Notifications go to members of the household the change
 * happened in. Join requests (`households/{id}/joinRequests/{uid}`) notify the
 * household's admin; whoever gets added to memberIds is welcomed.
 *
 * Data retention: the morning run deletes a household's tasks once they're
 * more than TASK_RETENTION_DAYS old.
 *
 * Device tokens live at `users/{uid}/fcmTokens/{token}` (written by the
 * app's NotificationService). A user can opt out with
 * `users/{uid}.pushNotificationsEnabled = false` (Settings > Notifications).
 *
 * Which notifications to send is decided by the pure functions in
 * ./notifications/plan.ts; this file only does the Firestore/FCM I/O.
 *
 * Delivery is at-most-once: Firestore triggers can fire more than once for
 * the same change, and scheduled runs can overlap, so every send is
 * "claimed" in Firestore first (see claimEvent and the household's nextRunAt).
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  onDocumentCreatedWithAuthContext,
  onDocumentUpdatedWithAuthContext,
  onDocumentWritten,
  onDocumentWrittenWithAuthContext,
} from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { initializeApp } from 'firebase-admin/app';
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type DocumentData,
  type DocumentReference,
} from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

import { buildMessage, type MessageContext } from './notifications/messages';
import {
  planDigest,
  planJoinRequested,
  planMembersAdded,
  planMorning,
  planRedemptionCreated,
  planTaskCreated,
  planTaskUpdated,
  type Audience,
  type MorningTask,
  type NotificationKind,
  type PlannedNotification,
  type TaskData,
} from './notifications/plan';
import {
  addDays,
  isValidTimeZone,
  localDay,
  nextLocalHour,
  occurrenceId,
  occurrencesBetween,
  parseRule,
  startOfDay,
} from './notifications/recurrence';

initializeApp();

// In-app account deletion (callable). See ./account/delete.ts.
export { deleteAccount } from './account/delete';
// Task proof photo retention.
export { cleanUpTaskPhotos, purgeExpiredTaskPhotos } from './photos/cleanup';
// Premium subscriptions (App Store / Google Play). See ./premium/index.ts.
export {
  verifyPurchase,
  appStoreNotifications,
  playStoreNotifications,
  refreshSubscriptions,
  syncHouseholdPremium,
  onPremiumGrantWritten,
} from './premium';
setGlobalOptions({ maxInstances: 10 });

const db = getFirestore();

const TASK_PATH = 'households/{householdId}/tasks/{taskId}';
/**
 * One marker doc per handled trigger event, so a redelivered event is not
 * sent twice. Admin-only (no client rules match it). Enable a Firestore TTL
 * policy on `expiresAt` for this collection group to purge old markers.
 */
const PROCESSED_EVENTS = 'notificationEvents';
const PROCESSED_EVENT_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/** gRPC status for "document already exists". */
const ALREADY_EXISTS = 6;
const REDEMPTION_PATH = 'households/{householdId}/redemptions/{redemptionId}';
const HOUSEHOLD_PATH = 'households/{householdId}';
const SCHEDULE_PATH = 'households/{householdId}/taskSchedules/{scheduleId}';
const JOIN_REQUEST_PATH = 'households/{householdId}/joinRequests/{userId}';
/** Tasks are deleted this many days after they were created (privacy). Keep in sync with AppConstants.taskDeleteAfterDays. */
const TASK_RETENTION_DAYS = 60;
/** Schedule fields only the server writes; changing them isn't an edit. */
const SCHEDULE_SERVER_FIELDS = ['generatedThrough'];
/** How far back the morning run looks for tasks (to archive missed occurrences). */
const MORNING_LOOKBACK_DAYS = 14;

/** FCM error codes meaning "this token is dead — forget it". */
const STALE_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// --- Firestore helpers -------------------------------------------------------

interface UserDoc {
  name?: string;
  role?: string;
  /** The household the user is currently viewing; membership is the household's memberIds. */
  householdId?: string | null;
  pushNotificationsEnabled?: boolean;
}

/** A household's member ids (empty if it doesn't exist). */
async function householdMemberIds(householdId: string): Promise<string[]> {
  const snap = await db.collection('households').doc(householdId).get();
  const ids = snap.data()?.memberIds;
  return Array.isArray(ids) ? ids.filter((x): x is string => typeof x === 'string') : [];
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
    scheduleId: d.scheduleId ?? null,
  };
}

/** A household's IANA time zone, or null if it hasn't been set yet. */
function householdZone(data: DocumentData | undefined): string | null {
  const tz = data?.timezone;
  return isValidTimeZone(tz) ? tz : null;
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
  // Only ever notify members of the household the change happened in.
  const members = await householdMemberIds(householdId);
  let candidates: string[];
  if (audience.type === 'user') {
    candidates = [audience.userId];
  } else if (audience.type === 'users') {
    candidates = audience.userIds;
  } else {
    candidates = members;
  }
  candidates = candidates.filter((id) => members.includes(id) && !excludeUserIds.includes(id));

  const wantedRole = audience.type === 'parents' ? 'parent' : audience.type === 'children' ? 'child' : null;
  const docs = await Promise.all(candidates.map((id) => users.get(id)));
  return candidates.filter((_, i) => {
    const user = docs[i];
    if (!user || user.pushNotificationsEnabled === false) return false;
    return wantedRole === null || user.role === wantedRole;
  });
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

/**
 * Records that trigger event [eventId] is being handled. Returns false if it
 * was already claimed — i.e. this is a duplicate delivery and must not send.
 */
async function claimEvent(eventId: string, source: string): Promise<boolean> {
  try {
    await db.collection(PROCESSED_EVENTS).doc(eventId).create({
      source,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + PROCESSED_EVENT_TTL_MS),
    });
    return true;
  } catch (err) {
    if ((err as { code?: unknown }).code === ALREADY_EXISTS) {
      logger.info('Duplicate event delivery skipped', { eventId, source });
      return false;
    }
    throw err;
  }
}

// --- Repeating tasks -----------------------------------------------------------

/**
 * Creates the task docs for [scheduleRef]'s occurrences after the schedule's
 * `generatedThrough` (or after [floor], whichever is later) up to [through],
 * and advances `generatedThrough`. One transaction, deterministic ids: safe
 * to call repeatedly and concurrently. A parent deleting a generated task
 * isn't undone, because days already generated are never revisited.
 */
async function generateOccurrences(
  scheduleRef: DocumentReference,
  tz: string,
  floor: string,
  through: string,
): Promise<number> {
  const tasks = scheduleRef.parent.parent!.collection('tasks');
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(scheduleRef);
    const data = snap.data();
    if (!data || data.archived === true) return 0;
    const rule = parseRule(data);
    if (!rule) {
      logger.warn('Skipping schedule with an invalid rule', { schedule: scheduleRef.path });
      return 0;
    }

    const done = typeof data.generatedThrough === 'string' ? data.generatedThrough : null;
    const after = done && done > floor ? done : floor;
    if (after >= through) return 0;

    const days = occurrencesBetween(rule, after, through);
    const refs = days.map((day) => tasks.doc(occurrenceId(scheduleRef.id, day)));
    const existing = refs.length ? await tx.getAll(...refs) : [];

    let created = 0;
    days.forEach((day, i) => {
      if (existing[i].exists) return;
      created++;
      tx.create(refs[i], {
        title: data.title ?? '',
        description: data.description ?? '',
        icon: data.icon ?? null,
        rewardXp: data.rewardXp ?? null,
        coinReward: data.coinReward ?? null,
        requiresPhoto: data.requiresPhoto === true,
        assignedToUserId: data.assignedToUserId ?? null,
        status: 'pending',
        archived: false,
        isRecurring: true,
        repeat: rule.repeat,
        scheduleId: scheduleRef.id,
        occurrenceDate: day,
        dueDate: Timestamp.fromDate(startOfDay(day, tz)),
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    tx.update(scheduleRef, { generatedThrough: through });
    return created;
  });
}

/** Deletes a schedule's not-yet-started occurrences after [today]. */
async function removeFutureOccurrences(householdRef: DocumentReference, scheduleId: string, today: string) {
  const snap = await householdRef.collection('tasks').where('scheduleId', '==', scheduleId).get();
  const doomed = snap.docs.filter((d) => {
    const t = d.data();
    // Keep anything a child has already claimed or started.
    return (
      typeof t.occurrenceDate === 'string' &&
      t.occurrenceDate > today &&
      (t.status ?? 'pending') === 'pending' &&
      !t.claimedBy
    );
  });
  for (let i = 0; i < doomed.length; i += 400) {
    const batch = db.batch();
    doomed.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return doomed.length;
}

/** Order-independent JSON of a value (Timestamps compare by value). */
function stableJson(v: unknown): string {
  if (v instanceof Timestamp) return `ts:${v.toMillis()}`;
  if (Array.isArray(v)) return `[${v.map(stableJson).join(',')}]`;
  if (v && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).sort().map((k) => `${JSON.stringify(k)}:${stableJson(o[k])}`).join(',')}}`;
  }
  return JSON.stringify(v) ?? 'undefined';
}

function withoutServerFields(data: DocumentData | undefined): string {
  if (!data) return '';
  const copy = { ...data };
  for (const f of SCHEDULE_SERVER_FIELDS) delete copy[f];
  return stableJson(copy);
}

// --- Data retention ------------------------------------------------------------

/** Deletes tasks created more than TASK_RETENTION_DAYS ago. Returns how many. */
async function purgeOldTasks(householdRef: DocumentReference, now: Date): Promise<number> {
  const cutoff = Timestamp.fromMillis(now.getTime() - TASK_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  const old = await householdRef.collection('tasks').where('createdAt', '<', cutoff).get();
  for (let i = 0; i < old.docs.length; i += 400) {
    const batch = db.batch();
    old.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return old.size;
}

// --- Morning run ---------------------------------------------------------------

/**
 * 9 AM in one household: top up repeating-task occurrences through
 * tomorrow, archive missed occurrences, and send each child one digest.
 */
async function runMorning(householdRef: DocumentReference, tz: string, now: Date): Promise<void> {
  const householdId = householdRef.id;
  const today = localDay(now, tz);
  const yesterday = addDays(today, -1);
  const tomorrow = addDays(today, 1);

  const schedules = await householdRef.collection('taskSchedules').get();
  for (const s of schedules.docs) {
    try {
      await generateOccurrences(s.ref, tz, yesterday, tomorrow);
    } catch (err) {
      logger.error('Generating occurrences failed', { schedule: s.ref.path, err });
    }
  }

  try {
    const purged = await purgeOldTasks(householdRef, now);
    if (purged) logger.info('Deleted old tasks', { householdId, purged });
  } catch (err) {
    logger.error('Deleting old tasks failed', { householdId, err });
  }

  const snap = await householdRef
    .collection('tasks')
    .where('dueDate', '>=', Timestamp.fromDate(startOfDay(addDays(today, -MORNING_LOOKBACK_DAYS), tz)))
    .where('dueDate', '<', Timestamp.fromDate(startOfDay(tomorrow, tz)))
    .get();

  const raw = new Map<string, DocumentData>();
  const tasks: MorningTask[] = [];
  for (const d of snap.docs) {
    const data = d.data();
    const due = data.dueDate as Timestamp | null | undefined;
    if (!due || typeof due.toDate !== 'function') continue;
    raw.set(d.id, data);
    tasks.push({
      id: d.id,
      title: data.title,
      assignedToUserId: data.assignedToUserId ?? null,
      status: data.status,
      archived: data.archived === true,
      day: localDay(due.toDate(), tz),
      scheduleId: data.scheduleId ?? null,
    });
  }

  const plan = planMorning(tasks, today, yesterday);

  if (plan.toArchive.length) {
    const batch = db.batch();
    plan.toArchive.forEach((id) => batch.update(householdRef.collection('tasks').doc(id), { archived: true, missed: true }));
    await batch.commit();
  }

  const users = new UserCache();
  const children = await resolveRecipients(householdId, { type: 'children' }, [], users);
  for (const childId of children) {
    const mine = plan.children.get(childId) ?? { due: [], overdue: [] };
    const digest = planDigest({ ...mine, pool: plan.pool });
    if (!digest) continue;
    try {
      if (digest.task) {
        const ctx = await taskContext(raw.get(digest.task.id), undefined, users);
        await sendToUsers([childId], digest.kind, ctx, { householdId, taskId: digest.task.id });
      } else {
        const titles = (list: MorningTask[]) => list.map((t) => t.title ?? '');
        await sendToUsers(
          [childId],
          digest.kind,
          { digest: { due: titles(mine.due), overdue: titles(mine.overdue), pool: titles(plan.pool) } },
          { householdId },
        );
      }
    } catch (err) {
      logger.error('Morning digest failed', { householdId, childId, err });
    }
  }
  logger.info('Morning run done', { householdId, today, children: children.length, archived: plan.toArchive.length });
}

// --- Triggers ----------------------------------------------------------------

/** New task: "new quest available" (pool) or "new quest assigned". */
export const notifyOnTaskCreated = onDocumentCreatedWithAuthContext(TASK_PATH, async (event) => {
  const raw = event.data?.data();
  if (!raw) return;

  const plans = planTaskCreated(toTaskData(raw), event.authId);
  logger.info('Task created', { taskId: event.params.taskId, actor: event.authId, plans: plans.map((p) => p.kind) });
  if (plans.length === 0) return;
  if (!(await claimEvent(event.id, 'notifyOnTaskCreated'))) return;

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
  if (!(await claimEvent(event.id, 'notifyOnTaskUpdated'))) return;

  const users = new UserCache();
  const ctx = await taskContext(after, event.authId, users);
  await dispatch(plans, event.params.householdId, ctx, { taskId: event.params.taskId }, users);
});

/** Child redeemed a reward: tell the parents. */
export const notifyOnRewardRedeemed = onDocumentCreatedWithAuthContext(REDEMPTION_PATH, async (event) => {
  const raw = event.data?.data();
  if (!raw) return;
  if (!(await claimEvent(event.id, 'notifyOnRewardRedeemed'))) return;

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
 * The morning run. Each household stores `nextRunAt` (its next 9 AM, in its
 * own time zone), so this only reads households that are actually due — an
 * indexed query that is usually empty — instead of scanning tasks. Runs on
 * the hour and half hour so half-hour zones (e.g. India) are on time too.
 *
 * `nextRunAt` is advanced in a transaction before the household is
 * processed, so overlapping runs can't double-send.
 */
export const runHouseholdMornings = onSchedule({ schedule: 'every 30 minutes', timeZone: 'UTC' }, async () => {
  const now = new Date();
  const due = await db.collection('households').where('nextRunAt', '<=', Timestamp.fromDate(now)).get();

  for (const doc of due.docs) {
    try {
      const tz = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        const data = fresh.data();
        const next = data?.nextRunAt as Timestamp | undefined;
        if (!data || !next || next.toMillis() > now.getTime()) return null;
        const zone = householdZone(data);
        // No zone: stop scheduling until the app sets one (see onHouseholdWritten).
        tx.update(doc.ref, { nextRunAt: zone ? Timestamp.fromDate(nextLocalHour(now, zone)) : FieldValue.delete() });
        return zone;
      });
      if (tz) await runMorning(doc.ref, tz, now);
    } catch (err) {
      logger.error('Morning run failed', { householdId: doc.id, err });
    }
  }
});

/** Someone entered the invite code: tell the household's admin. */
export const notifyOnJoinRequested = onDocumentCreatedWithAuthContext(JOIN_REQUEST_PATH, async (event) => {
  const raw = event.data?.data();
  if (!raw) return;
  const household = (await db.collection('households').doc(event.params.householdId).get()).data();
  const plans = planJoinRequested(household?.ownerId ?? null, event.params.userId);
  if (plans.length === 0) return;
  if (!(await claimEvent(event.id, 'notifyOnJoinRequested'))) return;

  const ctx: MessageContext = { requesterName: raw.name, householdName: household?.name };
  await dispatch(plans, event.params.householdId, ctx, { requesterId: event.params.userId }, new UserCache());
});

/**
 * Someone was added to a household (the admin approved their join request,
 * or a parent created a child account): welcome them. A brand-new
 * household's creator isn't welcomed.
 */
export const notifyOnMembersAdded = onDocumentWrittenWithAuthContext(HOUSEHOLD_PATH, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const plans = planMembersAdded(
    Array.isArray(before.memberIds) ? before.memberIds : [],
    Array.isArray(after.memberIds) ? after.memberIds : [],
    event.authId,
  );
  if (plans.length === 0) return;
  if (!(await claimEvent(event.id, 'notifyOnMembersAdded'))) return;
  await dispatch(plans, event.params.householdId, { householdName: after.name }, {}, new UserCache());
});

/** Keeps `nextRunAt` in step with the household's time zone. */
export const onHouseholdWritten = onDocumentWritten(HOUSEHOLD_PATH, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;

  const tz = householdZone(after);
  if (!tz) return;
  if (after.nextRunAt && householdZone(before) === tz) return; // already scheduled for this zone

  await event.data!.after.ref.update({ nextRunAt: Timestamp.fromDate(nextLocalHour(new Date(), tz)) });
  logger.info('Scheduled household mornings', { householdId: event.params.householdId, tz });
});

/**
 * A repeating task was created, edited or deleted. Edits and deletes drop
 * occurrences after today that haven't been started; creates and edits then
 * generate today's (if it falls today) and tomorrow's occurrences right away.
 */
export const onTaskScheduleWritten = onDocumentWritten(SCHEDULE_PATH, async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  // Ignore our own generatedThrough bookkeeping.
  if (before?.exists && after?.exists && withoutServerFields(before.data()) === withoutServerFields(after.data())) return;

  const householdRef = db.collection('households').doc(event.params.householdId);
  const tz = householdZone((await householdRef.get()).data());
  if (!tz) {
    logger.warn('Household has no time zone yet; occurrences wait for its first morning run', {
      householdId: event.params.householdId,
    });
    return;
  }
  const today = localDay(new Date(), tz);

  if (before?.exists) {
    const removed = await removeFutureOccurrences(householdRef, event.params.scheduleId, today);
    // Re-plan from today on (today's occurrence is kept/created, never duplicated).
    if (after?.exists) await after.ref.update({ generatedThrough: addDays(today, -1) });
    logger.info('Schedule changed', { scheduleId: event.params.scheduleId, removed });
  }
  if (after?.exists) {
    const created = await generateOccurrences(after.ref, tz, addDays(today, -1), addDays(today, 1));
    logger.info('Generated occurrences', { scheduleId: event.params.scheduleId, created });
  }
});
