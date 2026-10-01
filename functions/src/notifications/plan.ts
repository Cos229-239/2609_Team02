/**
 * Pure decision logic: given a Firestore change, which notifications
 * should go out and to whom. Kept free of any Firebase imports so it can
 * be unit tested with plain `node --test` (see plan.test.ts).
 */

export type NotificationKind =
  // To children
  | 'task_available' // new unassigned task in the shared pool
  | 'task_assigned' // a parent assigned a task to this child
  | 'task_due' // assigned task is due today
  | 'task_overdue' // assigned task is past due
  | 'task_approved' // a parent approved the child's completed task
  // To parents
  | 'task_accepted' // a child claimed a task from the pool
  | 'task_completed' // a child marked a task done (awaiting approval)
  | 'reward_redeemed'; // a child redeemed a reward from the store

export type Audience =
  | { type: 'user'; userId: string }
  | { type: 'children' }
  | { type: 'parents' };

export interface PlannedNotification {
  kind: NotificationKind;
  audience: Audience;
  /** Never notify these users (normally: whoever made the change). */
  excludeUserIds: string[];
}

/** The subset of a `households/{id}/tasks/{taskId}` doc the planner reads. */
export interface TaskData {
  title?: string;
  assignedToUserId?: string | null;
  status?: string;
  archived?: boolean;
  dueDate?: Date | null;
  /** Written by the app's `claimTask` — fallback when auth context is missing. */
  claimedBy?: string | null;
}

const exclude = (actorId: string | undefined): string[] => (actorId ? [actorId] : []);

/** A task document was created. */
export function planTaskCreated(task: TaskData, actorId?: string): PlannedNotification[] {
  if (task.archived) return [];
  if ((task.status ?? 'pending') !== 'pending') return [];

  const assignee = task.assignedToUserId ?? null;
  if (assignee) {
    if (assignee === actorId) return [];
    return [{ kind: 'task_assigned', audience: { type: 'user', userId: assignee }, excludeUserIds: [] }];
  }
  return [{ kind: 'task_available', audience: { type: 'children' }, excludeUserIds: exclude(actorId) }];
}

/** A task document was updated. */
export function planTaskUpdated(
  before: TaskData,
  after: TaskData,
  actorId?: string,
): PlannedNotification[] {
  if (after.archived) return [];

  const out: PlannedNotification[] = [];
  const assignee = after.assignedToUserId ?? null;

  // --- (Re)assignment ------------------------------------------------------
  if (assignee && assignee !== (before.assignedToUserId ?? null)) {
    const isClaim = actorId
      ? actorId === assignee
      : after.claimedBy === assignee && before.claimedBy !== assignee;

    if (isClaim) {
      out.push({ kind: 'task_accepted', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) });
    } else {
      out.push({ kind: 'task_assigned', audience: { type: 'user', userId: assignee }, excludeUserIds: [] });
    }
  }

  // --- Status transitions --------------------------------------------------
  const wasStatus = before.status ?? 'pending';
  const isStatus = after.status ?? 'pending';

  if (wasStatus !== 'completed' && isStatus === 'completed') {
    out.push({ kind: 'task_completed', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) });
  }

  if (wasStatus !== 'approved' && isStatus === 'approved' && assignee && assignee !== actorId) {
    out.push({ kind: 'task_approved', audience: { type: 'user', userId: assignee }, excludeUserIds: [] });
  }

  return out;
}

/** A redemption document was created. */
export function planRedemptionCreated(actorId?: string): PlannedNotification[] {
  return [{ kind: 'reward_redeemed', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) }];
}

// --- Due / overdue reminders ------------------------------------------------

const HOUR_MS = 60 * 60 * 1000;

/**
 * Every place the app writes `dueDate` (the date picker and the seeded
 * starter tasks in `TaskModel.defaultAvailableCatalog`) stores local
 * midnight of the due day, so offsets from it land at a local wall-clock
 * time without the server needing to know each family's time zone. A
 * `dueDate` with a time of day shifts its reminders by that much.
 */
/** "Due today" reminder: 3 PM on the due day (after school). */
export const DUE_REMINDER_OFFSET_MS = 15 * HOUR_MS;
/** "Past due" notice: 8 AM the day after the due day. */
export const OVERDUE_OFFSET_MS = (24 + 8) * HOUR_MS;
/**
 * Don't send stale reminders more than this long after they were due —
 * e.g. for old tasks the first time the sweep is deployed.
 */
export const LATE_GRACE_MS = 48 * HOUR_MS;

/**
 * Per-task record of which reminders went out, keyed by the dueDate (ms)
 * they were sent for — so moving the due date re-arms the reminders.
 */
export interface DueNotificationLog {
  dueFor?: number | null;
  overdueFor?: number | null;
}

/** Which reminder (if any) a task needs right now. */
export function planDueReminder(
  task: TaskData,
  now: Date,
  log: DueNotificationLog = {},
): 'task_due' | 'task_overdue' | null {
  const due = task.dueDate;
  if (!due || task.archived) return null;
  if ((task.status ?? 'pending') !== 'pending') return null;
  if (!task.assignedToUserId) return null;

  const key = due.getTime();
  const nowMs = now.getTime();
  const dueAt = key + DUE_REMINDER_OFFSET_MS;
  const overdueAt = key + OVERDUE_OFFSET_MS;

  if (nowMs >= overdueAt) {
    if (nowMs - overdueAt > LATE_GRACE_MS) return null;
    return log.overdueFor === key ? null : 'task_overdue';
  }
  if (nowMs >= dueAt) {
    return log.dueFor === key ? null : 'task_due';
  }
  return null;
}

/** dueDate window the scheduled sweep has to look at for a given `now`. */
export function dueSweepWindow(now: Date): { from: Date; to: Date } {
  const nowMs = now.getTime();
  return {
    from: new Date(nowMs - OVERDUE_OFFSET_MS - LATE_GRACE_MS),
    to: new Date(nowMs - DUE_REMINDER_OFFSET_MS),
  };
}
